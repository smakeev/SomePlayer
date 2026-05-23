# Architecture

SomePlayer is a Swift Package with one library target, `SomePlayer`. It supports iOS 17+ and macOS 14+.

## Layers

- `Public`: app-facing aliases and small models.
- `Engine`: `SomePlayerEngine`, event delivery, the audio serial executor, and the time/pitch playback graph.
- `Streaming`: downloading, parsing, reading, resumable data, and stream scheduling.
- `SilenceDetection`: audio tap analysis and silence-rate controllers.
- `Metadata`: ID3 and AVAsset metadata extraction.
- `Utilities`: shared helpers such as playback time formatting.

## Main Types

`SomePlayer` is a type alias for `SomePlayerEngine`, the main integration point for apps. It owns the current URL, download policy, playback controls, metadata state, timeline state, delegate emitter, and async event subscribers.

`TimePitchStreamer` subclasses `Streamer` and inserts the audio effects used by the public engine controls:

- Rate and pitch through `AVAudioUnitTimePitch`.
- Voice/global gain through `AVAudioUnitEQ`.

`AudioPipeline` serializes audio-side work on a custom serial executor. This keeps AVAudioEngine mutations, scheduling changes, and public command bodies ordered.

`DelegateEmitter` receives engine events from any thread and drains them on `@MainActor`. It coalesces high-frequency scalar fields and preserves FIFO ordering for edge events.

## Data Flow

```text
SomePlayerEngine
  -> ID3Parser
  -> TimePitchStreamer
  -> Downloader
  -> Parser
  -> Reader
  -> AVAudioPlayerNode
  -> AVAudioUnitTimePitch
  -> AVAudioUnitEQ
  -> mainMixerNode
```

The main mixer tap feeds audio power analysis, audio buffer snapshots, and silence-rate decisions back into the engine.

## Threading Model

The library is thread-safe for normal app use:

- Public commands enqueue onto `AudioPipeline`.
- Audio graph mutations run on the pipeline's serial executor.
- Latest scalar snapshots use `OSAllocatedUnfairLock`.
- Delegate callbacks are delivered on `@MainActor`.
- `PlayerEvent` streams use independent `AsyncStream` continuations protected by a lock.
- Audio tap buffers are copied into `AudioBufferSnapshot` before crossing thread boundaries.

Several AVFoundation-owning classes are marked `@unchecked Sendable` because the underlying reference types are not fully modeled by Swift's sendability system. The implementation confines mutable access through the mechanisms above.

## Observation Model

Use the delegate for UI that does not need every audio-tap event. It updates roughly every 100 ms and is already on `@MainActor`.

Use `subscribe()` when a consumer needs the full event stream. New subscribers first receive a replay of current coalesced state, then receive new events. Historical edge events are not replayed.

## Package Layout

```text
Sources/
  Public/
  Engine/
  Streaming/
    Download/
    Parse/
    Read/
    Stream/
  SilenceDetection/
  Metadata/
  Utilities/
Examples/
  SwiftUI/
  UIKitExample/
Docs/
```
