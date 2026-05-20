# SomePlayer

SomePlayer is a Swift Package for streaming audio playback with time pitch control and silence skipping experiments.

## Package

The library is exposed as the `SomePlayer` SwiftPM product:

```swift
.package(path: "path/to/SomePlayer")
```

Supported platforms:

- iOS 17+
- macOS 14+

## Layout

- `Sources/SomePlayer/Public` - thin public facade types for the current API.
- `Sources/SomePlayer/Engine` - playback engine and audio pipeline.
- `Sources/SomePlayer/Streaming` - downloading, parsing, reading, and streaming.
- `Sources/SomePlayer/SilenceDetection` - silence skipping processors and speed control.
- `Sources/SomePlayer/Metadata` - ID3 and asset metadata parsing.
- `Sources/SomePlayer/Utilities` - shared helpers and iOS-only utility views.
- `Examples/iOS/SomePlayerExample.xcodeproj` - current UIKit example wired to the local package.

The old library Xcode projects were removed; the package is the source of truth now.
