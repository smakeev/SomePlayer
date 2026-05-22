# Engine Audit — Bugs & Warnings

Read-only analysis of `Sources/Engine/*` and `Sources/Streaming/**`. Findings are ordered roughly top-to-bottom through the stack. Tags: `[THREAD]` concurrency/race, `[BUG]` correctness, `[LIFETIME]` retain/leak, `[STYLE]` clarity.

---

## TimePitchStreamer.swift / Streamer.swift

### 1. [THREAD][CRITICAL] Buffer-scheduling timer pinned to whatever runloop created the streamer
`Streamer.swift:162-179` — Timer is added to `RunLoop.current` from inside `setupAudioEngine()`, which runs from `init()`. `SomePlayerEngine.streamer` is a `lazy` property, so the runloop "current" depends on where the streamer is first accessed (almost always main).
- If first access ever happens off-main on a thread without a runloop, the timer silently never fires.
- In practice this runs on **main**, meaning the whole hot path (reader read → AudioConverter → schedule buffer + handleTimeUpdate + notify) is on main.

### 2. [THREAD][CRITICAL] Timer fires at sub-millisecond cadence
`Streamer.swift:161-162` — `interval = (1 / (44100/8192))/100` ≈ 1.86 ms, then divided by 2 → ~0.93 ms tick. The main runloop is woken ~1000×/sec to call `scheduleNextBuffer()`, `handleTimeUpdate()`, and `notifyTimeUpdated()`. Wildly excessive — will starve UI work.

### 3. [THREAD] Audio conversion done on main
`Streamer.swift:493-498` calls `reader.read(readBufferSize)` which calls `AudioConverterFillComplexBuffer` (`Reader.swift:100`). Synchronous CPU-bound conversion on the timer thread (= main).

### 4. [THREAD] Buffer-completion handler bounces freeBuffer back to main
`Streamer.swift:498-504` — `playerEngineNode.scheduleBuffer { ... DispatchQueue.main.async { ... reader.freeBuffer() } }`. The completion is invoked on AVAudio's render thread, then forced back to main for memory freeing — unnecessary load on main.

### 5. [THREAD][BUG] Data race on `Reader.buffers` / `bufferDescriptions`
`Reader.swift:21-39` — `freeBuffer()` and `removeAllBuffers()` mutate `buffers`/`bufferDescriptions` arrays WITHOUT `queue.sync`. Meanwhile:
- `read()` mutates them inside `queue.sync` (line 96-113)
- `ReaderConverterCallback` (`Reader+Converter.swift:58, 73`) mutates them from inside that sync
- `freeBuffer()` is called from main (line 502)
The reader's queue is a private serial queue, so main-thread `freeBuffer()` runs concurrently with another thread's `read()` if there ever is one. The mitigation today is "everything is on main anyway" — the queue is a lie.

### 6. [THREAD][BUG] Data race on `Parser.packets`
`Parser+Packets.swift:35,45` writes to `parser.packets` from the C callback (called inline during `parse(data:)`). `Reader+Converter.swift:37,51` reads it. **No synchronization.** Today both happen on main; if you move parsing/reading off-main, this will crash.

### 7. [THREAD][BUG] `installTap` writes `self.lastBuffer` from audio render thread, no sync
`PlayerEngine.swift:808-811` — tap closure stores `self.lastBuffer = buffer` from AVAudio's IO thread. `lastBuffer` is publicly readable from any thread (probably main). Plain Swift property → unsynchronized cross-thread access. UB.

### 8. [BUG] `currentPacket` mutated without protection in the converter callback
`Reader+Converter.swift:81` — `reader.currentPacket = reader.currentPacket + 1`. `Reader.seek()` (`Reader.swift:120`) wraps the same write in `queue.sync`. Inconsistent: if seek is ever called concurrently with a converter-fill, race.

### 9. [LIFETIME] Timer never invalidated on `stop()`/`reset()` — only in `deinit`
`Streamer.swift:194-196` — `scheduleNextBufferTimer` keeps ticking forever as long as the streamer is alive, even after `stop()`. The closure has `guard self?.state != .stopped` early-return, but the runloop is still being woken ~1000×/sec doing nothing.

### 10. [LIFETIME] `volumeRampTimer` not invalidated in `deinit`
`Streamer.swift:194-196` — only `scheduleNextBufferTimer` is invalidated. The volume ramp timer can outlive the streamer.

### 11. [BUG] `volumeRampTimer` math can divide by zero / produce NaN
`Streamer.swift:393` — `Timer(timeInterval: Double(Float((duration/2.0))/(newVolume * 10)), ...)`. If `newVolume == 0`, you get `inf`. If negative, you get a negative interval — undefined Timer behaviour.

### 12. [BUG] Buffer scheduling completion captures `reader` strongly across boundaries
`Streamer.swift:498-504` — the closure captures the local `reader` (the unwrapped value), not `self?.reader`. If `reset()` swaps out `self.reader`, the completion still calls `freeBuffer()` on the *old* reader. Possibly intentional; worth confirming.

### 13. [BUG] `lastSteppedPacket` is the only backpressure and it's mutated from two paths
`Streamer.swift:457-472` — incremented on the timer thread (~main), decremented in `DispatchQueue.main.async`. Currently safe because both are main, but the side effect of `didSet` (pausing/resuming the player node) is non-trivial logic to run from an async dispatch.

### 14. [BUG] `handleTimeUpdate()` fires `fileFinished` repeatedly
`Streamer.swift:544-558` — every timer tick after `currentTime + totalTimeOffset >= max(duration, totalDuration)` calls `seek(to: 0)`, `pause()`, and `delegate.fileFinished(...)`. The condition will not immediately be false (node is paused), so this can fire multiple times in a row. Needs a "did finish" guard.

### 15. [BUG] `seekPercently` uses `try!`
`PlayerEngine.swift:570` — `try! self.streamer.seek(to: 0, internalUse: true)`. A throw crashes the app.

### 16. [BUG] `progressiveSeek` mutated inside `waitForProgress` didSet
`Streamer.swift:86-117` — setting `waitForProgress = 0` triggers `seek(to: progressiveSeek)` from inside a property setter and mutates `progressiveSeek` in a `defer`. Fragile state machine; reads of these properties from elsewhere are not synchronized with this transition.

---

## Streamer+DownloadableDelegate.swift

### 17. [THREAD] Parser runs on whatever thread URLSession dispatches to
`Streamer+DownloadableDelegate.swift:36-77` — calls `parser.parse(data:)` synchronously. The `DispatchQueue.main.async` wrap is commented out. The downloader's URLSession is created with `delegateQueue: nil` → background serial queue — BUT `Downloader+URLSessionDelegate.swift:34` *does* dispatch the data callback to main. Two layers doing related work; easy to break by uncommenting one without the other. The de-facto contract that parsing is on main is implicit and undocumented.

### 18. [BUG] Dead `DispatchQueue.main.async` blocks left as comments throughout
Same file lines 14-16, 23-25, 31-33, 46-48 — large commented-out blocks. Hard to reason about thread expectations.

---

## Downloader.swift / Downloader+URLSessionDelegate.swift

### 19. [THREAD] Every URLSession callback hops to main
`Downloader+URLSessionDelegate.swift:14, 34, 46` — `didReceive response`, `didReceive data`, `didCompleteWithError` all use `DispatchQueue.main.async`. **All download data parsed on main.** Combined with #1-#3, the engine is a main-thread monolith.

### 20. [LIFETIME] Potential URLSession retain cycle
`Downloader.swift:17, 75, 101, 120` — `URLSession(... delegate: self ...)` strong-references `Downloader`. Cycle is broken only inside `didCompleteWithError` via `session.invalidateAndCancel()`. If the task is replaced (via `url=` didSet, `resume(...)`, or `stop()`-then-new-url) before completion, the previous session may leak. `Downloader.shared` makes this worse.

### 21. [BUG] `Downloader.shared` singleton vs. per-streamer instance
`Downloader.swift:25` defines a shared singleton, but `Streamer.downloader` (`Streamer.swift:36-40`) creates a fresh `Downloader()`. Singleton is unused but mutable state of a downloader (`url`, `state`, `task`) makes shared-instance use unsafe anyway.

### 22. [BUG] Verbose `print("[SomePlayerDebug]...")` left in production paths
`Downloader+URLSessionDelegate.swift:26, 37, 50, 62` and `PlayerEngine.swift:290, 293, 591` — debug logs in shipping code. Each `didReceive data` print is per-chunk during streaming.

### 23. [BUG] `didCompleteWithError` sets `state = .completed` *then* possibly `.completedWithError`
`Downloader+URLSessionDelegate.swift:48-61` — two state writes back-to-back, each fires the `didSet` delegate notification. Delegate sees `.completed` then `.completedWithError`.

### 24. [TYPO] `self.self.totalBytesReceived`
`Downloader+URLSessionDelegate.swift:64` — duplicated `self.self`. Compiles but is a smell.

---

## PlayerEngine.swift

### 25. [THREAD] `state` didSet runs `streamer.totalDuration = 0` on the setting thread
`PlayerEngine.swift:134-149` — delegate notification is dispatched to main, but `streamer.totalDuration = 0` line is OUTSIDE the dispatch. State is set from many places, including delegate callbacks coming from the downloader. If you fix the threading, this will mutate streamer state from a background thread.

### 26. [THREAD] `handleMeta` mutates `self.id3Parser` from a global queue with no synchronization
`PlayerEngine.swift:368-374` — `self.id3Parser?.cancel()` + `self.id3Parser = ID3Parser(url)` both happen on `DispatchQueue.global()`. If `openRemote`/`openLocal` is called twice rapidly, two background jobs race on `id3Parser`.

### 27. [THREAD] Observer dictionaries unsynchronized
`PlayerEngine.swift:124-131` (`isGoodForStreamObservers`) and `649-656` (`rateObservers`) — `Dictionary` mutated and iterated with no lock. Today everything is main, but the contract is undocumented.

### 28. [BUG] `resetPlaybackStateForOpening` nils delegate, then restores — but async notifications are still in flight
`PlayerEngine.swift:441-472` — pattern is `delegate = nil; ...mutations...; delegate = oldDelegate`. Mutations during this window fire `DispatchQueue.main.async` notifications (e.g., `state` didSet line 137) that *queue up* and run *after* the delegate is restored. Suppression doesn't work for async callbacks.

### 29. [BUG] `totalSize` didSet recomputes bitrate every byte
`PlayerEngine.swift:242-246` — `hasBytes += bytes` (line 775) can set `totalSize = hasBytes` via `hasBytes` didSet, which fires `totalSize` didSet, which divides by `self.duration`. Per-chunk on every download packet. If `duration` is 0, you get `inf` stored in `aboutBitrate`.

### 30. [BUG] `aboutBitrate` chicken-and-egg with `duration`
`PlayerEngine.swift:244` — early downloads will store NaN/inf bitrate (duration is 0), then `offset` didSet uses `aboutBitrate` to compute `timeOffset` (line 269), propagating bad values.

### 31. [BUG] `installTap` may be installed twice if state transitions to playing without an intervening stop
`PlayerEngine.swift:789-818` — `streamer(_,changedState:)` installs/removes tap based on the new state. If two consecutive `.playing` states are reported (which the current state machine can do, see #23), `installTap` is called twice without `removeTap` → AVAudioEngine assert.

### 32. [BUG] `hasError = true` set on download failure but `state` not transitioned
`PlayerEngine.swift:767-771` — error path stores resumable data, fires delegate, but doesn't update `state`. The engine reports `failed` only on engine/parser/scheduleBuffer failures.

### 33. [BUG] `streamer(_, isBuffering:)` re-fires delegate unconditionally
`Streamer.swift:132-138` already de-duplicates, but `PlayerEngine.swift:742-745` re-fires the delegate unconditionally — works today only because of de-dup upstream. Fragile coupling.

### 34. [BUG] `seekPercently` percent==1 branch only handles `.stream`
`PlayerEngine.swift:567-574` — explicit "if percent == 1 && downloadingPolicy != .progressiveDownload" — predownload and progressive can fall through to other branches with surprising behavior.

### 35. [BUG] `reset()` doesn't reset `silenceHandlingType`, observers, or other public state
`PlayerEngine.swift:490-505` — only resets playback state. Probably intentional, worth confirming.

### 36. [STYLE] `unsafeBitCast(self, to: UnsafeMutableRawPointer.self)`
`Parser.swift:61`, `Reader.swift:97` — should be `Unmanaged.passUnretained(self).toOpaque()` for clarity and correctness of refcount semantics.

---

## Root cause summary

Everything funnels onto main because:
1. The buffer scheduling timer is on main (#1).
2. The downloader force-dispatches every chunk to main (#19).
3. The buffer-completion handler bounces back to main (#4).
4. State/delegate notifications dispatch to main from `didSet`s (#25 and scattered).

`Reader` / `Parser` / `AudioConverter` all run on main, and the "thread-safety" affordances in `Reader.queue` and `Parser` are vestigial — they only "work" because nothing contends for them. The moment any one piece moves off main, races #5, #6, #7, #8 will surface.
