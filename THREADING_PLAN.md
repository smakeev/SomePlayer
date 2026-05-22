# Engine Threading Refactor — Plan

Companion to `ENGINE_AUDIT.md`. Describes the target architecture for moving `SomePlayerEngine` + `Streamer` off the main thread using Swift Concurrency, while preserving a synchronous, fire-and-forget public API.

---

## Goals

- **Same public surface, callable from any thread.** `engine.play()`, `engine.seek(to:)`, `engine.rate = 1.5` all return immediately. No `async`/`await` at the call site.
- **No data races inside the engine.** Logical races (UI lag, "set rate to 1.5 then immediately read 1.4") are acceptable. Cross-thread heap corruption / undefined behaviour is not.
- **One unit of work at a time inside the engine.** Actors used as serial command queues — no reentrancy.
- **Delegate notifications on `MainActor`, throttled per-event-type.**
- **Edge-triggered events (state, errors, finished) never coalesced or dropped.**
- **Strict-concurrency clean** (`-strict-concurrency=complete` / Swift 6 mode).

## Non-goals (for this pass)

- Bounded download backpressure (single-URL workload; unbounded queue is fine).
- Multi-segment / partial-range cache reuse (existing bug, separate task).
- Solving UI "snap-back" lag when fire-and-forget setters race with `didChange` events (deferred).

---

## Architecture

### Isolation domains

```
┌──────────────────────────────────────────────────────────────┐
│  Caller threads (any)                                        │
│  ───────────────                                             │
│  engine.play() / seek() / volume = … (sync, fire-and-forget) │
└──────────────────┬───────────────────────────────────────────┘
                   │  enqueue command (non-blocking)
                   ▼
┌──────────────────────────────────────────────────────────────┐
│  AudioActor   (custom SerialExecutor, dedicated thread)      │
│  ──────────                                                  │
│  - Owns: AVAudioEngine config, Parser, Reader,               │
│           Downloader-driver, scheduling state machine        │
│  - All command methods are NON-suspending                    │
│  - C callbacks (parser/converter) execute on this thread     │
│  - Long-running consumers (download stream, throttle wake)   │
│    run as separate Tasks that CALL INTO actor methods,       │
│    they are not actor methods themselves                     │
└────────────────┬──────────────────────┬──────────────────────┘
                 │ pending events       │ AsyncStream yield
                 │ (OSAllocatedUnfairLock)
                 ▼                      ▼
┌────────────────────────────┐  ┌─────────────────────────────┐
│  MainActor                 │  │  Public AsyncStream         │
│  ─────────                 │  │  ──────────────────         │
│  DelegateEmitter Task      │  │  subscribe() → fresh stream │
│  - 10 Hz wake              │  │  - Full-rate, every event   │
│  - Drains pending events   │  │  - Multi-subscriber via     │
│  - Calls @MainActor        │  │    factory                  │
│    delegate per event type │  │  - Background-safe          │
└────────────────────────────┘  └─────────────────────────────┘

┌──────────────────────────────────────────────────────────────┐
│  AVAudio render thread   (owned by AVAudio — untouchable)    │
│  - installTap callback writes to lock-protected snapshot box │
│  - Never calls into AudioActor (no await, no Task spawn)     │
└──────────────────────────────────────────────────────────────┘
```

### Why a custom `SerialExecutor`

Default Swift actors hop between cooperative pool threads. For AVAudioEngine config calls and to keep C callbacks (`AudioFileStreamParseBytes`, `AudioConverterFillComplexBuffer`) consistently on the same thread, we back the audio actor with a `SerialExecutor` whose `enqueue` dispatches onto a dedicated `DispatchQueue(label: "engine.audio", qos: .userInitiated)`. Effectively serial → effectively single-thread for AVAudio's purposes.

### Why "actors as queues" works without custom non-reentrant executor

Reentrancy only happens at `await` points. **Rule:** no public/private method on `AudioActor` contains an `await` in its body. Long-running work is structured as separate `Task`s that call back into the actor through non-suspending methods. Examples:

- Downloader feeds an `AsyncStream<Data>`; a detached consumer `Task` does `for await data in stream { await actor.didReceiveData(data) }`. Each call to `didReceiveData` is a single non-suspending unit; actor processes them one at a time, FIFO.
- Time-update throttle: a `Task.sleep(100ms)` loop on the audio actor's executor, but implemented as a detached `Task` that calls `actor.flushPendingEvents()` (non-suspending).
- Seek's network/parse wait: spawn a child `Task` that, when ready, calls `actor.didCompleteSeek(...)`. The original `seek()` method returns immediately.

This way the actor's methods are atomic units; reentrancy is structurally impossible.

---

## Public API changes

### Removed

- `addRateObserver(withId:observer:)` / `removeRateObserver(withId:)`
- `addIsGoodForStreamObservers(withId:observer:)` / `removeIsGoodForStreamObservers(withId:)`

### Added

```swift
public extension SomePlayerEngine {
    /// Fresh stream per subscriber; not multicast — each subscribe() returns
    /// an independent AsyncStream backed by its own continuation.
    func subscribe() -> AsyncStream<PlayerEvent>
}

public enum PlayerEvent: Sendable {
    case stateChanged(SomePlayerEngine.PlayerEngineState)
    case currentTimeUpdated(TimeInterval)
    case durationUpdated(TimeInterval)
    case downloadProgressUpdated(progress: Float, taskProgress: Float, url: URL)
    case savedSecondsUpdated(TimeInterval)
    case offsetChanged(Int64)
    case imageChanged(SomePlayerImage)
    case titleChanged(String)
    case artistChanged(String)
    case albumChanged(String)
    case bufferingChanged(Bool)
    case waitingForDownloaderChanged(Bool)
    case downloadFailed(error: Error, url: URL)
    case failure(SomePlayerEngine.FailureType)
    case rateChanged(Float)
    case isGoodForStreamChanged(Bool)
    case audioBufferTap(AudioBufferSnapshot)
    case seekFailed(Error)
}

public struct AudioBufferSnapshot: Sendable {
    public let samples: [[Float]]            // per channel
    public let sampleRate: Double
    public let frameLength: AVAudioFrameCount
    public let timestamp: AVAudioTime?
}
```

### Changed

- `SomeplayerEngineDelegate` becomes `@MainActor`-isolated. All conforming types must be `@MainActor`. (Source-breaking for any non-main implementor.)
- `lastBuffer: AVAudioPCMBuffer?` replaced by `lastBufferSnapshot: AudioBufferSnapshot?` (lock-protected; readable from any thread). Tap delivers via the `audioBufferTap` event on the stream as well.
- `func seek(to:)` no longer `throws`. Failures arrive as `seekFailed(Error)` via delegate + stream.
- New `delegate` callback added: `playerEngine(_, seekFailed: Error)`.

### Unchanged

- All other method signatures, property types, semantics.
- `state`, `currentTime`, `duration`, `volume`, `rate`, `pitch`, etc. remain sync gettable from any thread (backed by a `Snapshot` lock — see below).

---

## Command queue / cancellation policy

Each public method enqueues a command of a specific kind. The actor maintains `var inflight: [CommandKind: Task<Void, Never>]`. Enqueue rules:

| Command kind     | On new enqueue                                  | Priority         |
|------------------|-------------------------------------------------|------------------|
| `openRemote` / `openLocal` | Cancel **all** in-flight tasks of every kind. Reset state. | `.userInitiated` |
| `seek`           | Cancel previous `seek` (if any). FIFO with non-seek commands. | `.userInitiated` |
| `play` / `pause` | Cancel previous `play`/`pause` (coalesce to latest). | `.userInitiated` |
| `setRate` / `setVolume` / `setPitch` / `setGlobalGain` | Cancel previous of same kind (coalesce-latest). | `.userInitiated` |
| `setBaseRate`    | Cancel previous `setBaseRate`. | `.userInitiated` |
| `resume` / `restart` | Cancel previous `resume`/`restart`. | `.userInitiated` |
| `reset`          | Cancel **all** in-flight tasks of every kind, then run. | `.userInitiated` |
| Internal: `didReceiveData` | FIFO, never cancelled by user commands (except by `openRemote`/`reset` which discard). | `.utility` |
| Internal: `bufferConsumed` | FIFO. | `.utility` |
| Internal: `tapSnapshot` | Coalesce-latest. | `.utility` |

Snapshot of "user-visible state" (used by sync getters) is updated **before** the Task is enqueued, so reads after writes appear consistent immediately — even though the underlying AVAudio mutation happens later. (Logical-race-only is by design.)

---

## Concurrency rules (enforced)

1. **No `await` inside any `AudioActor` method.** Long work splits into separate Tasks that re-enter via non-suspending actor methods.
2. **No lock held across an `await`.** Lock-protected snapshots use `withLock { return value }` patterns; the value is then used outside the lock.
3. **`Parser`, `Reader` are non-actor classes**, private to `AudioActor`. Their C callbacks mutate their own state directly — safe because the surrounding call is on the actor's executor. They are never exposed or passed to other isolation domains.
4. **AVAudio render thread (tap callback) never touches the actor.** It writes to an `OSAllocatedUnfairLock<AudioBufferSnapshot?>` slot. The actor consumes it on its own schedule.
5. **All `Task` creation captures `[weak self]`** and checks at the top of each non-suspending re-entry. `deinit` calls `.cancel()` on each in-flight Task; Tasks must drop self-references on cancel.
6. **Sendable boundary**: every type yielded into `AsyncStream` and every value passed to a delegate method must be `Sendable`. Audited at compile time.

---

## Delegate throttling

Pending events live in a single `Sendable` struct, guarded by an `OSAllocatedUnfairLock`:

```swift
struct PendingEvents: Sendable {
    // coalesce-latest
    var time: TimeInterval?
    var duration: TimeInterval?
    var downloadProgress: (Float, Float, URL)?
    var savedSeconds: TimeInterval?
    var rate: Float?
    var isGoodForStream: Bool?
    var bufferingChanged: Bool?
    var waitingForDownloader: Bool?
    var lastBufferSnapshot: AudioBufferSnapshot?
    // edge-triggered FIFO (never dropped)
    var edgeEvents: [PlayerEvent] = []
    var generation: UInt64 = 0    // bumped on openRemote/reset
}
```

A `@MainActor` `DelegateEmitter` runs a Task that:

1. `await Task.sleep(for: .milliseconds(100))` — 10 Hz tick.
2. Atomically drains the pending struct, capturing snapshot + generation.
3. Fires `edgeEvents` in order first (each as its own delegate call).
4. Fires one delegate call per non-nil coalesced field.
5. Loops, with cancellation check.

Edge-triggered events that need lower latency than 100 ms (errors, `failure`) get a "wake" signal that cuts the sleep short (implemented via an `AsyncStream<Void>` continuation; emitter `await`s on either the timer OR the wake channel using `Task.select`-style cancellation).

Generation counter: when `openRemote(newURL)` runs, it bumps the generation and clears coalesced fields. Any in-flight emission with the old generation is discarded — UI won't briefly flash old-track values.

The **full-rate `AsyncStream`** (`subscribe()`) bypasses the throttle. Every event yields immediately to all active continuations. Consumers that need everything (analytics, SwiftUI's `.task`) get it there; consumers that want throttled main-thread delivery use the delegate.

---

## Timers → Task.sleep + cancellation

Replaced:

| Old (Timer)                                | New                                                      |
|--------------------------------------------|----------------------------------------------------------|
| `scheduleNextBufferTimer` (~1 kHz)         | **Removed.** Scheduling driven by `scheduleBuffer` completion + downloader-data signals. |
| `volumeRampTimer`                          | `Task` on `AudioActor` running `for _ in 0..<n { try await Task.sleep(...); applyStep() }`, with `Task.isCancelled` check each iteration. Replaced on each new ramp. |
| Throttle emitter                           | `@MainActor` Task with `Task.sleep(for: .milliseconds(100))` + wake channel. |

All Tasks store their `Task` handle; `deinit` and `reset()` cancel them.

---

## Downloader

- `Downloader` becomes a non-actor `final class` with `Sendable` conformance via `@unchecked Sendable` (it owns mutable `URLSession`/`task` but synchronizes them on a private serial queue or uses `OSAllocatedUnfairLock`).
- URLSession callbacks no longer hop to main. Instead they yield into a private `AsyncStream<DownloadEvent>` continuation.
- A detached consumer Task `for await event in stream` calls `audioActor.handleDownloadEvent(event)` (non-suspending).
- URLSession retain cycle fix: `URLSession` is invalidated and recreated on every `url=` swap. Tracked via a small `var currentSession: URLSession?` that is `invalidateAndCancel()`-ed before replacement.
- `Downloader.shared` singleton removed (dead code, and unsafe semantically).

---

## AVAudio interaction rules

- `engine.attach/connect/prepare/start/stop/installTap/removeTap` — all called from the audio actor only.
- `playerEngineNode.play/pause/stop/scheduleBuffer/scheduleSegment/scheduleFile` — all on the audio actor.
- `playerEngineNode.lastRenderTime` / `playerTime(forNodeTime:)` — documented thread-safe, but we read them from the audio actor anyway for consistency.
- Tap callback writes to:
  ```swift
  let tapSnapshotBox = OSAllocatedUnfairLock<AudioBufferSnapshot?>(initialState: nil)
  ```
  The actor reads-and-clears on its tap-snapshot command (coalesce-latest) and yields the snapshot to `PendingEvents.lastBufferSnapshot` + the AsyncStream.

---

## Sendable audit checklist

- [ ] `SomePlayerEngine` (final class, `@unchecked Sendable` — actor-isolated internals + lock-protected snapshot)
- [ ] `SomePlayerImage` (UIImage/NSImage are Sendable in current SDKs — verify)
- [ ] `Error` payloads in events (Swift 6 `Error: Sendable`)
- [ ] `ResumableData` — needs to be `Sendable` (audit its `URLResponse` field — `URLResponse` *is* `Sendable`)
- [ ] All closures crossing actor boundaries marked `@Sendable`
- [ ] `AVAudioPCMBuffer` removed from public API (replaced by snapshot)

---

## Implementation phases

Each phase compiles and passes existing tests before the next begins.

### Phase 1 — Plumbing & API additions, no behaviour change

- Add `PlayerEvent`, `AudioBufferSnapshot`, `subscribe()`. Wire current delegate emissions to also yield into the stream's continuations (everything still on main).
- Add the new `delegate` method `playerEngine(_, seekFailed:)`.
- Turn on `-strict-concurrency=complete` for the package; fix any easy diagnostics that don't require the actor (mark obvious `@Sendable`, `Sendable`).

### Phase 2 — Introduce `AudioActor`, move scheduling off-main

- Custom `SerialExecutor` backed by a dedicated dispatch queue.
- Move `Parser`, `Reader`, AVAudio scheduling, buffer-completion handling into the actor.
- Replace `scheduleNextBufferTimer` with completion-driven scheduling + a 100 ms time-update tick.
- Keep delegate emission on main (existing behaviour).
- Add `PendingEvents` + 10 Hz `DelegateEmitter`.
- Remove `Downloader+URLSessionDelegate`'s `DispatchQueue.main.async` wrappers; replace with `AsyncStream<DownloadEvent>` consumer.
- Replace `volumeRampTimer` with `Task.sleep`.

### Phase 3 — Command queue & cancellation

- `[CommandKind: Task]` infrastructure.
- Apply per-kind cancellation rules per the table above.
- Add `Snapshot` lock-protected struct for sync getters.

### Phase 4 — Remove observer API, finalise public surface

- Delete `addRateObserver`/`addIsGoodForStreamObservers` and all related observer state.
- Update SwiftUI example to use `subscribe()`; add comment block:
  ```swift
  // Example of consuming the full-rate event stream. Use this for analytics,
  // debug logging, or any consumer that doesn't need MainActor delivery.
  // For UI binding, prefer the @MainActor delegate (throttled to ~10 Hz).
  Task {
      for await event in engine.subscribe() {
          print("[Engine event]", event)
      }
  }
  ```
- Mark `SomeplayerEngineDelegate` `@MainActor`.
- Replace `lastBuffer` with `lastBufferSnapshot`.

### Phase 5 — Audit & cleanup

- TSan run with the SwiftUI example exercising play/pause/seek under load.
- Strict-concurrency clean (no warnings, no `@unchecked` except where justified with a comment).
- Remove `Downloader.shared`.
- Delete dead `DispatchQueue.main.async` comment blocks.
- Fix remaining audit items: `try!` in `seekPercently`, `divide-by-zero` in volume ramp math, double `state` write in `didCompleteWithError`, `self.self.totalBytesReceived` typo, repeated `fileFinished` firing, bitrate computed on duration==0.

---

## Resolved

- **`subscribe()` semantics**: new subscriber receives only events that occur after subscription begins. No replay buffer. On engine `deinit`, all active continuations are `finish()`-ed. Default `AsyncStream` buffering policy (`.unbounded`) — slow consumers will see memory grow; acceptable for now.
- **Wake-signal**: implementer's choice. Will use a tiny `AsyncStream<Void>` channel for cancellable sleep.
- **"Snap-back" UI lag**: separate task, post-refactor. Likely solved on the UI side (ignore delegate values for a window after issuing a command) rather than in the engine.
