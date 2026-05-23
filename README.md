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
        eventTask = Task { [weak self] in
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

## Lower-Level Public API

Most apps should use `SomePlayer`. The following types are public because the engine is built from composable streaming pieces and the tests/examples use them directly.

### `TimePitchStreamer`

`TimePitchStreamer` subclasses `Streamer` and adds:

- `timePitchNode`: `AVAudioUnitTimePitch` used for rate and pitch.
- `voiceBoostNode`: `AVAudioUnitEQ` used for global gain.
- `pitch`: pitch in cents.
- `rate`: playback rate.
- `globalGain`: EQ gain in `-96...24` dB.

### `Streamer` And `Streaming`

`Streamer` is the AVAudioEngine-backed streaming implementation. The `Streaming` protocol exposes:

- State: `currentTime`, `duration`, `state`, `url`, `delegate`.
- Pipeline pieces: `downloader`, `parser`, `reader`.
- Audio graph: `engine`, `playerEngineNode`, `readBufferSize`, `readFormat`, `volume`.
- Commands: `play()`, `pause()`, `stop()`, `resume(_:)`, `seek(to:internalUse:)`.

`StreamingState` values are `.stopped`, `.paused`, and `.playing`.

`StreamingDelegate` receives streamer-level file completion, range header, download progress/failure, state, time, duration, format, buffering, downloader-wait, and engine failure callbacks. `SomePlayerEngine` implements this delegate and translates those callbacks into the app-facing delegate and event stream.

### `Downloader`, `Downloading`, And `DownloadEvent`

`Downloader` implements `Downloading` with `URLSession`. The protocol exposes `events`, `completionHandler`, `progress`, `state`, `url`, `simulatedChunkDelayMilliseconds`, and the commands `start()`, `pause()`, `stop()`, and `resume(_:)`.

`DownloadingState` values are `.completed`, `.completedWithError`, `.started`, `.paused`, `.notStarted`, and `.stopped`.

`DownloadEvent` values are:

- `.stateChanged`
- `.rangeHeader`
- `.data`
- `.completed`

### `Parser`, `Parsing`, And `ParserError`

`Parser` implements `Parsing` with Audio File Stream Services. The protocol exposes parsed `dataFormat`, estimated `duration`, completion state, parsed `packets`, `totalFrameCount`, `totalPacketCount`, `formatObserver`, `parse(data:)`, and offset helpers for time/frame/packet conversion.

`ParserError` values are `.streamCouldNotOpen` and `.failedToParseBytes`.

### `Reader`, `Reading`, And `ReaderError`

`Reader` implements `Reading` and converts parsed packets into LPCM `AVAudioPCMBuffer` instances for the engine. The protocol exposes buffer storage, `currentPacket`, `parser`, `readFormat`, `read(_:)`, `seek(_:)`, and `freeBuffer()`.

`ReaderError` values cover converter failures, destination format creation, PCM buffer creation, missing parser format, insufficient data, end of file, and queue locking.

### `AudioPipeline` And `AudioExecutor`

`AudioPipeline` is an actor isolated to `AudioExecutor`, a custom serial executor. It owns keyed tasks for public commands and long-running scheduling work. Public methods include `run`, `cancel`, `cancelAll`, `cancelPublicCommands`, `perform`, and `startScheduling`.

### `ID3Parser`

`ID3Parser` extracts stream metadata and asset/header information. `ID3Parser.isGoodForStream(_:handler:)` checks whether a URL has stream-friendly metadata, and engine opens use parser instances internally to populate title, artist, album, artwork, duration, and header size.

### `ResumableData`

`ResumableData` stores byte offset, ready-data count, and HTTP validator information used when resuming a range-capable download.

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
