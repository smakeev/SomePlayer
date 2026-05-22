# Engine Audit — Open Items

Companion to `THREADING_PLAN.md`. Items closed by Phases 1–4 have been pruned. Remaining work is the Phase 5 cleanup queue + a few design questions.

Tags: `[THREAD]` concurrency/race, `[BUG]` correctness, `[LIFETIME]` retain/leak, `[STYLE]` clarity, `[DESIGN]` open question.

---

## Streamer.swift

### #12 [DESIGN] `scheduleBuffer` completion captures the old `reader` strongly
`Streamer.swift` — the closure captures the local `reader` (from `guard let reader = reader`) rather than `self.reader`. If `reset()` swaps the reader, the completion still calls `freeBuffer()` on the *old* reader. This is correct (you want the old reader to free its own allocations), but worth pinning down explicitly: the old reader stays alive until all its scheduled buffers play through.

### #14 [BUG] `handleTimeUpdate()` fires `fileFinished` repeatedly
`Streamer.swift:handleTimeUpdate` — after the end condition is met, `seek(to: 0)` + `pause()` are called, but the condition `currentTime + totalTimeOffset >= max(duration, totalDuration)` may still hold for one or more subsequent ticks. The delegate sees `fileFinished` multiple times. Needs a "did-finish" latch cleared by the next successful seek/open.

### #16 [BUG] `progressiveSeek` mutated inside `waitForProgress` didSet
`Streamer.swift` — setting `waitForProgress = 0` triggers `seek(to: progressiveSeek)` from inside the property setter and mutates `progressiveSeek` in a `defer`. Fragile state machine; reads of these properties from other paths are not synchronized with this transition. Worth refactoring into an explicit state-transition method.

---

## Downloader.swift / Downloader+URLSessionDelegate.swift

### #20 [LIFETIME] `URLSession` retain cycle on every URL swap
`Downloader.swift` — `URLSession(... delegate: self ...)` strong-references `Downloader`. The cycle is only broken in `didCompleteWithError` via `session.invalidateAndCancel()`. If the task is replaced (via `url=` didSet or `resume(...)`) before completion, the previous session leaks. Fix: invalidate the previous session before assigning a new one in every path that replaces `self.session`.

### #21 [BUG] `Downloader.shared` singleton kept for test back-compat
`Downloader.swift` — the singleton is `nonisolated(unsafe)`; the engine no longer uses it (per-instance now), but tests still reference it. Remove the singleton and migrate tests to per-instance `Downloader()`.

---

## PlayerEngine.swift

### #25 [THREAD] `state` didSet runs `streamer.totalDuration = 0` on the setting thread
`PlayerEngine.swift` — the delegate emission is enqueued to the throttled `MainActor` emitter, but `if state == .initializing { streamer.totalDuration = 0 }` happens synchronously on whatever thread set state. Most callers are now on the audio executor (good), but a couple of paths (`handleMeta` completion via `DispatchQueue.main.async`, `format` didSet from the parser callback) can still set state from off-executor. Route `streamer.totalDuration = 0` through the audio pipeline.

### #26 [THREAD] `handleMeta` mutates `self.id3Parser` from a global queue
`PlayerEngine.swift:handleMeta` — `self.id3Parser?.cancel(); self.id3Parser = ID3Parser(url)` runs on `DispatchQueue.global()`. Commands are serialised now (open/reset use `enqueueExclusive`), so the racey window is narrower, but the `id3Parser` mutation itself is unprotected. Best fix: move ID3 parsing onto the audio pipeline (or its own actor) and have the completion call back through a non-isolated event the `.open` task awaits.

### #28 [BUG] `resetPlaybackStateForOpening` nils delegate then restores
`PlayerEngine.swift:556-586` — pattern is `delegate = nil; ...mutations...; delegate = oldDelegate`. State mutations during this window enqueue notifications into the `DelegateEmitter` (lock-protected). The emitter's next tick will fire those — but they'll find `delegate` already restored, so suppression doesn't work for emitter-routed events either. Either drop the nil-trick (it doesn't help any more) or have the emitter snapshot the delegate at enqueue time and drop events whose snapshot is nil.

### #29 [BUG] `totalSize` didSet recomputes bitrate every byte
`PlayerEngine.swift` — `hasBytes += bytes` (in `streamer(_, updatedDownloadProgress:...)`) may bump `totalSize`, which triggers `aboutBitrate = (Double(totalSize - headerSize) * 8) / duration`. Runs per chunk. Wasteful, and divides by zero before duration is known (see #30).

### #30 [BUG] `aboutBitrate` chicken-and-egg with `duration`
`PlayerEngine.swift` — early chunks store NaN/inf in `aboutBitrate` because `duration == 0` at that point. `offset` didSet then uses `aboutBitrate` to compute `timeOffset`, propagating the bad value. Compute bitrate only when `duration > 0`, and recompute on first valid `duration`.

### #31 [BUG] `installTap` may be installed twice
`PlayerEngine.swift:streamer(_, changedState:)` — installs/removes the main-mixer tap based on the streaming state. If two consecutive `.playing` transitions ever fire without an intervening `.stopped/.paused`, the second `installTap` will assert. Track an explicit "tap installed" flag.

### #32 [BUG] `hasError = true` on download failure doesn't transition `state`
`PlayerEngine.swift:streamer(_, failedDownloadWithError:...)` — error path stores resumable data and emits an edge event, but the engine state is unchanged. Decide whether downloader failures should bring `state` to `.failed` (probably yes for stream / progressive policies).

### #34 [BUG] `seekPercently` percent==1 branch only handles `.stream`
`PlayerEngine.swift:seekPercentlyDirect` — explicit `if percent == 1 && downloadingPolicy != .progressiveDownload` short-circuits to `.ended`. Predownload and progressive can fall through to other branches with surprising behavior.

### #35 [DESIGN] `reset()` doesn't reset `silenceHandlingType` or other public settings
`PlayerEngine.swift:reset()` — only resets playback state. Possibly intentional (user-tuned settings persist across track changes), but worth confirming.

---

## Parser.swift

### #36 [STYLE] `unsafeBitCast(self, to: UnsafeMutableRawPointer.self)`
`Parser.swift:69` — should use `Unmanaged.passUnretained(self).toOpaque()` for clarity and correct refcount semantics. Same fix as already applied in `Reader.swift`.

---

## Parser+PropertyListener.swift

### #PL47 [STYLE] Generic `&value` inout to `UnsafeMutableRawPointer`
`Parser+PropertyListener.swift:47` — `AudioFileStreamGetProperty(..., &value)` with generic `T` triggers a strict-concurrency warning (`forming UnsafeMutableRawPointer to a variable of type 'T'`). The lone remaining warning under `-warnings-as-errors`. Fix by specialising the helper or by using `withUnsafeMutablePointer`.
