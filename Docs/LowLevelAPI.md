# Low-Level Public API

`SomePlayerEngine` (aliased as `SomePlayer`) is the recommended integration point for apps. Underneath, the engine composes smaller streaming pieces, and those pieces are public for two reasons:

- The test suite drives each layer in isolation (`DownloaderTests`, `ParserTests`, `ReaderTests`).
- Advanced integrations can swap or wrap individual stages — for example, plug a different downloader, run the parser/reader against a custom byte source, or share the audio executor with non-engine work.

Normal apps do not need this surface. The types listed here are stable enough to use directly, but each carries more responsibility (and more invariants to preserve) than the high-level API.

## `TimePitchStreamer`

`TimePitchStreamer` subclasses `Streamer` and adds the audio effects used by the public engine controls:

- `timePitchNode`: `AVAudioUnitTimePitch` used for rate and pitch.
- `voiceBoostNode`: `AVAudioUnitEQ` used for global gain.
- `pitch`: pitch in `AVAudioUnitTimePitch` cents.
- `rate`: playback rate.
- `globalGain`: EQ gain in `-96...24` dB.

The node graph is `AVAudioPlayerNode -> AVAudioUnitTimePitch -> AVAudioUnitEQ -> mainMixerNode`. Use this directly when you need the time/pitch graph without the engine's metadata, event, or download-policy layers.

## `Streamer` And `Streaming`

`Streamer` is the AVAudioEngine-backed streaming implementation. The `Streaming` protocol exposes:

- State: `currentTime`, `duration`, `state`, `url`, `delegate`.
- Pipeline pieces: `downloader`, `parser`, `reader`.
- Audio graph: `engine`, `playerEngineNode`, `readBufferSize`, `readFormat`, `volume`.
- Commands: `play()`, `pause()`, `stop()`, `resume(_:)`, `seek(to:internalUse:)`.

`StreamingState` values are `.stopped`, `.paused`, and `.playing`.

`StreamingDelegate` receives streamer-level callbacks: file completion, range header, download progress/failure, state, time, duration, format, buffering, downloader-wait, and engine failure. `SomePlayerEngine` implements this delegate and translates the callbacks into the app-facing delegate and event stream.

Use `Streamer` directly when you want the scheduling pipeline without the engine's higher-level state machine, metadata extraction, or `PlayerEvent` stream.

## `Downloader`, `Downloading`, And `DownloadEvent`

`Downloader` implements `Downloading` with `URLSession`. The protocol exposes `events`, `completionHandler`, `progress`, `state`, `url`, `simulatedChunkDelayMilliseconds`, and the commands `start()`, `pause()`, `stop()`, and `resume(_:)`.

`DownloadingState` values are `.completed`, `.completedWithError`, `.started`, `.paused`, `.notStarted`, and `.stopped`.

`DownloadEvent` values are:

- `.stateChanged`
- `.rangeHeader`
- `.data`
- `.completed`

Use the downloader directly to consume the byte stream and range-header signals outside the engine — for example, to prefetch into your own cache.

## `Parser`, `Parsing`, And `ParserError`

`Parser` implements `Parsing` with Audio File Stream Services. The protocol exposes parsed `dataFormat`, estimated `duration`, completion state, parsed `packets`, `totalFrameCount`, `totalPacketCount`, `formatObserver`, `parse(data:)`, and offset helpers for time/frame/packet conversion.

`ParserError` values are `.streamCouldNotOpen` and `.failedToParseBytes`.

Use the parser directly when you have a byte source and want native audio packets plus format/duration information without scheduling them for playback.

## `Reader`, `Reading`, And `ReaderError`

`Reader` implements `Reading` and converts parsed packets into LPCM `AVAudioPCMBuffer` instances for the engine. The protocol exposes buffer storage, `currentPacket`, `parser`, `readFormat`, `read(_:)`, `seek(_:)`, and `freeBuffer()`.

`ReaderError` covers converter failures, destination format creation, PCM buffer creation, missing parser format, insufficient data, end of file, and queue locking.

Use the reader directly when you need PCM buffers in a specific format (for analysis, transcoding, or feeding a non-engine output) and already have a `Parser`.

## `AudioPipeline` And `AudioExecutor`

`AudioPipeline` is an actor isolated to `AudioExecutor`, a custom serial executor. It owns keyed tasks for public commands and long-running scheduling work. Public methods include `run`, `cancel`, `cancelAll`, `cancelPublicCommands`, `perform`, and `startScheduling`.

Use the pipeline directly to serialize your own audio-side work onto the same executor the engine uses — useful when extending the engine or composing additional AVAudioEngine work that must stay ordered with engine commands.

## `ID3Parser`

`ID3Parser` extracts stream metadata and asset/header information. `ID3Parser.isGoodForStream(_:handler:)` checks whether a URL has stream-friendly metadata; engine opens use parser instances internally to populate title, artist, album, artwork, duration, and header size.

Use it directly to probe a URL before deciding to play it (e.g. validating an item in a playlist), or to extract metadata without standing up a full engine.

## `ResumableData`

`ResumableData` stores byte offset, ready-data count, and HTTP validator information used when resuming a range-capable download.

Use it directly when bridging the downloader to your own resume/seek logic — for example, persisting partial-download state across app launches.

## Stability And Compatibility

These types are public, but they sit below the engine's public surface and may evolve when the engine's internals change. If you depend on them:

- Pin to a specific package version rather than tracking `main`.
- Treat protocol conformances as guidance rather than long-term contracts.
- Prefer `SomePlayer` for anything covered by the high-level API.
