# Streaming Pipeline

The streaming path is layered around `SomePlayerEngine`, `TimePitchStreamer`, and AVFoundation:

1. `SomePlayerEngine` receives `openRemote(_:)` or `openLocal(_:)`, resets playback state, and starts metadata extraction.
2. `ID3Parser` reads stream metadata and optional asset duration/header information.
3. `TimePitchStreamer` configures the AVAudioEngine graph.
4. `Downloader` fetches remote bytes and reports range support, progress, completion, and failures.
5. `Parser` converts incoming bytes into native audio packets using Audio File Stream Services.
6. `Reader` converts parsed packets into `AVAudioPCMBuffer` data for scheduling.
7. `Streamer` schedules buffers on `AVAudioPlayerNode` and reports time, duration, buffering, and state changes.
8. `SomePlayerEngine` translates streamer updates into delegate callbacks and `PlayerEvent` values.

## Downloading Policies

`SomePlayerEngine.PlayerEngineDownloadingPolicy` controls how a remote URL is consumed.

### `.stream`

Stream mode plays while bytes are arriving. If the server supports range requests, seeking outside the downloaded window updates the byte offset and restarts downloading from that position. If the target is already inside the downloaded window, the engine seeks within buffered data.

### `.progressiveDownload`

Progressive mode also plays while downloading, but far seeks wait for the active download to reach the requested position. During this wait, `isWaitingForDownloader` is true and `timelineState` can expose the pending seek position.

### `.predownload`

Predownload mode waits for the complete file before moving to `.ready`. Once the file is available, seeking uses local downloaded data.

## Remote Files

For remote URLs, the downloader reports:

- Whether the server accepts range requests.
- Total content length when known.
- Per-task progress.
- Received data chunks.
- Completion or error.

The engine tracks `offset`, `hasBytes`, `totalSize`, `headerSize`, `lastDownloadProgress`, and `fileDownloaded` from those events. `timelineState` maps these values to a slider model that can represent either seconds or bytes depending on range support and download state.

## Local Files

`openLocal(_:)` marks the item as already downloaded and opens it through the same parser/reader/scheduler path. The engine still extracts metadata, duration, artwork, and format information.

## Parsing And Reading

`Parser` progressively parses incoming data into packet data and packet descriptions. It exposes parsed format, packet counts, frame counts, duration estimates, and time/frame/packet offset helpers.

`Reader` consumes parser packets and produces `AVAudioPCMBuffer` instances in the streamer's read format. It owns converter state and supports packet-based seeking.

## Scheduling

`Streamer` owns the `AVAudioEngine`, `AVAudioPlayerNode`, parser, reader, and downloader. `TimePitchStreamer` adds:

- `AVAudioUnitTimePitch` for rate and pitch.
- `AVAudioUnitEQ` for global voice gain.

The node graph is:

```text
AVAudioPlayerNode -> AVAudioUnitTimePitch -> AVAudioUnitEQ -> mainMixerNode
```

Scheduling runs through `AudioPipeline`, an actor isolated to a serial `AudioExecutor`. Public commands such as play, pause, seek, reset, and tuning changes enqueue work by task key; a newer task of the same key replaces the previous pending task.

## Observation

The engine exposes two observation layers:

- `SomeplayerEngineDelegate`: throttled `@MainActor` delivery for UI.
- `subscribe()`: full-rate `AsyncStream<PlayerEvent>` for analytics, debugging, or custom state pipelines.

Delegate scalar fields are coalesced to the latest value per tick. Edge events such as state changes, failures, download failures, and seek failures are delivered FIFO.
