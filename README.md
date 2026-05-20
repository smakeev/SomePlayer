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

- `Sources/Public` - thin public facade types for the current API.
- `Sources/Engine` - playback engine and audio pipeline.
- `Sources/Streaming` - downloading, parsing, reading, and streaming.
- `Sources/SilenceDetection` - silence skipping processors and speed control.
- `Sources/Metadata` - ID3 and asset metadata parsing.
- `Sources/Utilities` - shared helpers without UI dependencies.
- `Examples/UIKitExample/SomePlayerUIKitExample.xcodeproj` - current UIKit example wired to the local package.
- `Examples/SwiftUI/SomePlayerSwiftUIExample.xcodeproj` - standalone SwiftUI example with separate iOS and macOS app targets.

The old library Xcode projects were removed; the package is the source of truth now.
