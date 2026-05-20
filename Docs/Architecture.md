# Architecture

SomePlayer is organized as a Swift Package with one library target, `SomePlayer`.

The current implementation still keeps most original type names intact to reduce migration risk. The new folders define ownership boundaries first; deeper API cleanup can happen after the example UI is modernized.

## Layers

- `Public` exposes the package-facing aliases and lightweight models.
- `Engine` owns `SomePlayerEngine` and the playback pipeline.
- `Streaming` owns downloader, parser, reader, and stream state.
- `SilenceDetection` owns smart speed and silence skipping processors.
- `Metadata` owns ID3 parsing.
- `Utilities` contains small shared helpers plus UIKit-only compatibility views guarded by `canImport(UIKit)`.
