# Engine Audit — Open Items

Companion to `THREADING_PLAN.md`. Items closed by Phases 1–5 have been pruned. Remaining work is a few design questions plus the items not enumerated for phase 5.

Tags: `[THREAD]` concurrency/race, `[BUG]` correctness, `[LIFETIME]` retain/leak, `[STYLE]` clarity, `[DESIGN]` open question.

---

## PlayerEngine.swift

### #28 [BUG] `resetPlaybackStateForOpening` nils delegate then restores
`PlayerEngine.swift:556-586` — pattern is `delegate = nil; ...mutations...; delegate = oldDelegate`. State mutations during this window enqueue notifications into the `DelegateEmitter` (lock-protected). The emitter's next tick will fire those — but they'll find `delegate` already restored, so suppression doesn't work for emitter-routed events either. Either drop the nil-trick (it doesn't help any more) or have the emitter snapshot the delegate at enqueue time and drop events whose snapshot is nil.

### #31 [BUG] `installTap` may be installed twice
`PlayerEngine.swift:streamer(_, changedState:)` — installs/removes the main-mixer tap based on the streaming state. If two consecutive `.playing` transitions ever fire without an intervening `.stopped/.paused`, the second `installTap` will assert. Track an explicit "tap installed" flag.

### #32 [BUG] `hasError = true` on download failure doesn't transition `state`
`PlayerEngine.swift:streamer(_, failedDownloadWithError:...)` — error path stores resumable data and emits an edge event, but the engine state is unchanged. Decide whether downloader failures should bring `state` to `.failed` (probably yes for stream / progressive policies).

### #34 [BUG] `seekPercently` percent==1 branch only handles `.stream`
`PlayerEngine.swift:seekPercentlyDirect` — explicit `if percent == 1 && downloadingPolicy != .progressiveDownload` short-circuits to `.ended`. Predownload and progressive can fall through to other branches with surprising behavior.

