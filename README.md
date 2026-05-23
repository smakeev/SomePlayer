# SomePlayer

SomePlayer is a Swift Package for streaming and local audio playback on iOS and macOS. It wraps an `AVAudioEngine` pipeline with remote download support, time/pitch control, voice gain, silence handling, metadata extraction, timeline helpers, delegate callbacks, and an async event stream.

## Package

Add the package with the SSH GitHub URL:

```swift
.package(url: "git@github.com:smakeev/SomePlayer.git", branch: "main")
```

Then depend on the library product:

```swift
.product(name: "SomePlayer", package: "SomePlayer")
```

Supported platforms:

- iOS 17+
- macOS 14+

## Quick Usage

```swift
import SomePlayer
import SwiftUI

@MainActor
final class PlayerModel: ObservableObject {
    private let player = SomePlayer(.stream)
    private var eventTask: Task<Void, Never>?

    @Published var state: SomePlayerState = .undefined
    @Published var timeline = SomePlaybackTimelineState(
        currentTime: 0,
        duration: 0,
        currentTimeText: "00:00",
        durationText: "00:00",
        sliderValue: 0,
        sliderMaximumValue: 1,
        downloadProgress: 0,
        offsetProgress: 0
    )

    init() {
        player.baseRate = 1.2
        player.silenceHandlingType = .adaptiveSpeed

        let events = player.subscribe()
        eventTask = Task.detached { [weak self] in
            for await event in events {
                await self?.handle(event)
            }
        }

        player.openRemote(URL(string: "https://example.com/audio.mp3")!)
    }

    func togglePlayback() {
        if state == .playing {
            player.pause()
        } else {
            player.play()
        }
    }

    func seek(percent: Float) {
        player.seekPercently(to: percent)
    }

    private func handle(_ event: PlayerEvent) {
        switch event {
        case .stateChanged(let value):
            state = value
        case .currentTimeUpdated, .durationUpdated, .downloadProgressUpdated, .offsetChanged:
            timeline = player.timelineState
        default:
            break
        }
    }
}
```

On iOS, configure `AVAudioSession` for playback before starting audio.

### Observation: delegate vs. `subscribe()`

For typical UI binding (state, current time, duration, download progress, metadata, buffering), prefer `SomeplayerEngineDelegate`. The engine's `DelegateEmitter` already throttles delivery on `@MainActor` (~10 Hz) and coalesces scalar fields to the latest value per tick, so you can drive SwiftUI directly from delegate callbacks without further work.

`subscribe()` returns the full-rate, unthrottled event stream. It emits as fast as the audio executor produces events and includes high-frequency cases (`audioBufferTap`, `currentTimeUpdated`, `downloadProgressUpdated`, `rateChanged` while silence-skipping is active). Use it for analytics, debug logging, custom derived state, or to observe events the delegate doesn't surface — not as a general UI binding.

When you do consume `subscribe()`, prefer a detached task (as in the example above) so the loop runs off the main thread and only the actual UI mutation pays the MainActor hop. If the consuming task inherits `MainActor` isolation, every event — even ones you ignore — wakes the main thread. If you must update UI from `subscribe()` and the event is not rare, throttle the updates yourself (and reconsider whether the delegate covers your case — it usually does).

## Examples

The main example is the SwiftUI project at `Examples/SwiftUI/SomePlayerSwiftUIExample.xcodeproj`. It contains shared UI plus separate macOS and iOS app targets:

- `Examples/SwiftUI/macOS/SomePlayerSwiftUIMacApp.swift`
- `Examples/SwiftUI/iOS/SomePlayerSwiftUIiOSApp.swift`
- `Examples/SwiftUI/Shared/PlayerDemoView.swift`
- `Examples/SwiftUI/Shared/PlayerDemoViewModel.swift`

The UIKit project at `Examples/UIKitExample/SomePlayerUIKitExample.xcodeproj` is an older example.

## Thread Safety

`SomePlayerEngine` is designed for cross-thread use. Public playback commands enqueue work onto the audio pipeline's serial executor, and latest-value snapshots are protected by `OSAllocatedUnfairLock`. Delegate delivery is drained on `@MainActor` by `DelegateEmitter` at roughly 10 Hz, with scalar events coalesced to the latest value and edge events delivered FIFO. `subscribe()` returns independent `AsyncStream<PlayerEvent>` streams and can be consumed from any task; callers should hop to `MainActor` before mutating UI state.

The engine and several pipeline classes use `@unchecked Sendable` because they wrap AVFoundation reference types. Their mutable runtime paths are serialized through the audio executor, lock-protected snapshots, or main-actor delegate delivery.

## Public API

### Type Aliases

- `SomePlayer`: alias for `SomePlayerEngine`.
- `SomePlayerState`: alias for `SomePlayerEngine.PlayerEngineState`.
- `SomeSilenceSkippingMode`: alias for `SomePlayerEngine.SilenceHandlingType`.
- `SomePlayerImage`: `UIImage` on UIKit platforms and `NSImage` on AppKit platforms.

### `SomePlayerItem`

Lightweight model for an item URL and optional title:

```swift
SomePlayerItem(url: url, title: "Episode title")
```

### `SomePlayerEngine`

Create an engine with a downloading policy:

```swift
let player = SomePlayer(.stream)
```

Downloading policies:

- `.stream`: starts playback while downloading; range-capable remote files can restart from a requested byte offset for seeks outside the downloaded window.
- `.progressiveDownload`: starts playback while downloading and waits for the active download to reach far seek targets.
- `.predownload`: downloads the full file before moving to `.ready`.

Playback state:

- `.undefined`: no active item is ready.
- `.initializing`: metadata and stream setup are running.
- `.ready`: playback can start.
- `.playing`: audio is playing.
- `.paused`: playback is paused.
- `.ended`: playback reached the end.
- `.failed`: the engine or scheduling pipeline failed.

Failure types:

- `.engineStart`: `AVAudioEngine` failed to start.
- `.scheduleBuffer`: scheduling an audio buffer failed.
- `.createParser`: stream parser creation failed.

Opening and control:

- `openRemote(_:)`: open a remote URL.
- `openLocal(_:)`: open a local file URL.
- `play()`: start or resume playback.
- `pause()`: pause playback.
- `resume()`: resume downloading after a recoverable download interruption.
- `restart()`: reset the stream and resume from the current item.
- `reset()`: restore engine state and tunable settings to defaults, then reload the current URL when present.
- `seek(to:)`: seek by playback time.
- `seekPercently(to:)`: seek by `0...1` fraction of the item.
- `noAssetNeeded(duration:)`: provide a known duration and skip asset duration loading when possible.

Playback controls:

- `baseRate`: user-selected baseline playback rate. Setting it also updates `rate`.
- `rate`: current applied playback rate. Silence handling may adjust this above `baseRate`.
- `pitch`: pitch shift in AVAudioUnitTimePitch cents.
- `volume`: player node volume.
- `globalGain`: EQ gain, accepted in `-96...24` dB. Setting it resets silence-rate state back to `baseRate`.
- `silenceHandlingType`: `.none`, `.smart`, `.speedUp`, or `.adaptiveSpeed`.
- `simulatedDownloadChunkDelayMilliseconds`: optional per-chunk download delay for testing slow streaming behavior.

Timeline and stream state:

- `state`: current `SomePlayerState`.
- `currentTime`, `formattedCurrentTime`: current playback time.
- `duration`, `formattedDuration`: best known duration, using parsed or estimated duration.
- `timelineState`: UI-ready `SomePlaybackTimelineState`.
- `downloadProgress`: available through `timelineState.downloadProgress` and delegate/event callbacks.
- `offset`, `offsetProgress`: byte offset used when range seeking.
- `rangeHeader`: whether the remote server supports range requests.
- `totalSize`, `headerSize`, `hasBytes`, `aboutBitrate`: current stream sizing and bitrate estimates.
- `fileDownloaded`: whether the current item is fully available.
- `isBuffering`: whether the streamer is buffering.
- `isWaitingForDownloader`: progressive-download mode is waiting for bytes needed by a pending seek.
- `isGoodForStream`: metadata parser found stream-friendly header information.
- `sampleRate`: parsed stream sample rate when available.
- `url`, `isLocal`: current source.

Metadata:

- `title`, `artist`, `album`: metadata extracted from the asset when available.
- `image`: artwork as `SomePlayerImage`.

Audio analysis:

- `averagePowerForChannel0`, `averagePowerForChannel1`: latest main-mixer RMS power in decibels.
- `lastBufferSnapshot`: sendable copy of the latest main-mixer tap buffer.

Observation:

- `delegate`: receives throttled `@MainActor` callbacks through `SomeplayerEngineDelegate`.
- `subscribe()`: returns an independent `AsyncStream<PlayerEvent>` with an initial replay of current coalesced state followed by full-rate events.
- `delegateEmitter`: exposed for tests and advanced integration; typical consumers set `delegate` instead.

### `SomeplayerEngineDelegate`

Delegate callbacks are delivered on `@MainActor`:

- `updatedDownloadProgress progress:currentTaskProgress:forURL:` reports total progress and current task progress.
- `changedState` reports playback state transitions.
- `updatedCurrentTime` and `updatedDuration` report timeline changes.
- `savedSeconds` reports time saved by silence handling.
- `offsetChanged` reports range-seek byte offset changes.
- `changedImage`, `changedTitle`, `changedArtist`, `changedAlbum` report metadata.
- `isBuffering` and `isWaitingForDownloader` report streaming waits.
- `failedDownloadWithError` reports download failures.
- `failedWithException` reports engine failures.
- `seekFailed` reports seek errors and has a default empty implementation.

### `PlayerEvent`

`subscribe()` emits:

- State and timeline: `.stateChanged`, `.currentTimeUpdated`, `.durationUpdated`.
- Downloading: `.downloadProgressUpdated`, `.downloadFailed`, `.offsetChanged`, `.isGoodForStreamChanged`.
- Metadata: `.imageChanged`, `.titleChanged`, `.artistChanged`, `.albumChanged`.
- Buffering: `.bufferingChanged`, `.waitingForDownloaderChanged`.
- Playback controls: `.rateChanged`, `.baseRateChanged`, `.pitchChanged`, `.volumeChanged`, `.globalGainChanged`, `.silenceHandlingTypeChanged`.
- Silence handling: `.savedSecondsUpdated`.
- Audio tap: `.audioBufferTap`.
- Failures: `.failure`, `.seekFailed`.

### `SomePlaybackTimelineState`

UI-ready timeline snapshot:

- `currentTime`, `duration`: numeric timeline values.
- `currentTimeText`, `durationText`: formatted strings.
- `sliderValue`, `sliderMaximumValue`: values for a time or byte-based slider.
- `downloadProgress`: total download progress in `0...1`.
- `offsetProgress`: current range offset progress in `0...1`.

### `AudioBufferSnapshot`

Sendable audio tap payload:

- `samples`: per-channel floating-point samples.
- `sampleRate`: buffer sample rate.
- `frameLength`: frame count.
- `sampleTime`: tap sample time when available.

### `SomePlaybackTimeFormatter`

Formats `TimeInterval` values as `mm:ss` or `hh:mm:ss`:

```swift
let text = SomePlaybackTimeFormatter.string(from: 65) // "01:05"
```

## Silence Skipping And Saved Time

`SomePlayerEngine` can transparently speed up quiet sections of audio while keeping pitch stable through `AVAudioUnitTimePitch`. Select a mode with `player.silenceHandlingType`:

- `.none` — leaves playback at `baseRate`.
- `.smart` — keeps a rolling window of recent loudness, uses the upper percentile as a speech/loudness reference, and gently raises rate when the current buffer is quieter than that reference. Capped at `baseRate + 0.75`, with small per-tap steps. Good general-purpose default.
- `.speedUp` — threshold-and-hysteresis silence detection. Targets a fixed `2.5x` while silent and `baseRate` while speech is detected. Attack engages quickly; release is more gradual.
- `.adaptiveSpeed` — builds a rolling loudness model with quiet/speech reference percentiles, maps current loudness into a curved silence score (with a dead zone and a minimum dynamic range so low-contrast content stays stable), and applies a proportional rate boost. Capped at `baseRate + 0.55`, with conservative smoothing.

Seeking and playback state changes reset the silence controller; the effective rate returns to `baseRate`. The currently applied rate is exposed via `player.rate` and emitted as `PlayerEvent.rateChanged(_:)` (which can fire frequently while silence-skipping is active).

When silence skipping runs above `baseRate`, the engine estimates how much real time was saved on each audio-tap buffer and emits it through:

- `SomeplayerEngineDelegate.playerEngine(_:savedSeconds:)`
- `PlayerEvent.savedSecondsUpdated(_:)`

Each delivery is a per-buffer delta — accumulate the values for a session total. See `Docs/SilenceSkipping.md` for the full algorithm description and `Docs/Architecture.md` / `Docs/StreamingPipeline.md` for the surrounding engine design.

## Lower-Level Public API

The engine is composed from smaller streaming pieces, each exposed publicly so the test suite can drive layers in isolation and so advanced integrations can swap or wrap individual stages. Typical apps don't need them — use `SomePlayer` instead.

- `TimePitchStreamer` — `Streamer` plus the rate/pitch and global-gain audio nodes. Use to drive the time-pitch audio graph without the engine's higher-level layers.
- `Streamer` / `Streaming` / `StreamingDelegate` / `StreamingState` — the AVAudioEngine-backed scheduling pipeline. Use to schedule playback without the engine's state machine, metadata, or `PlayerEvent` stream.
- `Downloader` / `Downloading` / `DownloadingState` / `DownloadEvent` — `URLSession`-based byte fetcher with range-header support. Use to consume the byte stream outside the engine, e.g. for prefetching into your own cache.
- `Parser` / `Parsing` / `ParserError` — Audio File Stream Services parser producing native audio packets and format/duration info. Use when you have a byte source and want packets without playing them.
- `Reader` / `Reading` / `ReaderError` — packet-to-LPCM `AVAudioPCMBuffer` converter. Use to obtain PCM buffers for analysis, transcoding, or non-engine output.
- `AudioPipeline` / `AudioExecutor` — actor + custom serial executor that owns the audio-side work queue. Use to serialize your own audio-side work onto the same executor the engine uses.
- `ID3Parser` — stream and asset metadata extraction (`isGoodForStream(_:handler:)`, title/artist/album/artwork/duration). Use to probe a URL or extract metadata without standing up a full engine.
- `ResumableData` — byte offset, ready-data count, and HTTP validator info for resuming range-capable downloads. Use when bridging the downloader to your own resume/seek logic.

See `Docs/LowLevelAPI.md` for the per-type member lists, intended use cases, and stability notes.

## Layout

- `Sources/Public` - app-facing aliases and lightweight models.
- `Sources/Engine` - player engine, event stream, delegate emitter, audio executor, and time/pitch streamer.
- `Sources/Streaming` - downloader, parser, reader, stream state, and resumable data.
- `Sources/SilenceDetection` - silence analysis and adaptive rate controllers.
- `Sources/Metadata` - ID3 and asset metadata parsing.
- `Sources/Utilities` - shared helpers.
- `Examples/SwiftUI` - main macOS and iOS example.
- `Examples/UIKitExample` - older UIKit example.
- `Docs` - implementation notes for architecture, streaming, and silence handling.
