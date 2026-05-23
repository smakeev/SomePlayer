# Silence Skipping

SomePlayer can adjust playback rate from the main-mixer audio tap while keeping pitch stable through `AVAudioUnitTimePitch`. The public switch is:

```swift
player.silenceHandlingType = .adaptiveSpeed
```

Available modes:

- `.none`: leaves playback at `baseRate`.
- `.smart`: continuously raises rate when current loudness is low compared with recent louder audio.
- `.speedUp`: uses threshold-based silence detection and moves toward a fixed high rate during silence.
- `.adaptiveSpeed`: builds a rolling loudness model and applies a curved rate boost for quieter sections.

## Audio Analysis

`SilenceAudioAnalyzer` reads `AVAudioPCMBuffer.floatChannelData` from the main mixer tap. For each channel it computes RMS power and converts the result to decibels. It also computes a combined power level across all channels.

The engine stores:

- `averagePowerForChannel0`
- `averagePowerForChannel1`
- `lastBufferSnapshot`

These values are lock-protected snapshots and are safe to read from any thread. `lastBufferSnapshot` is a sendable copy of audio samples, not the live `AVAudioPCMBuffer`.

## Rate Application

All silence-rate decisions run through `SilenceRateController`. The controller returns a target rate plus smoothing parameters:

- `targetRate`: rate the algorithm wants.
- `maxRate`: upper bound for the current mode.
- `maxStep`: maximum rate delta per tap decision.
- `smoothing`: interpolation amount from current rate to target rate.
- `shouldReportSavedTime`: whether the engine should emit saved-time events.

The engine clamps each target to `baseRate...maxRate`, smooths it, limits it by `maxStep`, and writes the result to the time-pitch node. Seeking and playback state changes reset the silence controller and return the effective rate to `baseRate`.

## `.smart`

Smart mode is a relative-loudness algorithm. It keeps a short window of recent loudness values, uses the upper percentile as a speech/loudness reference, and increases rate when the current buffer is quieter than that reference.

It also has enter and exit thresholds for silence state:

- Enter silence after several buffers below the quiet threshold.
- Exit silence after several buffers above the speech threshold.

The silence state affects how strongly the loudness gap contributes to the boost. Smart mode is capped at `baseRate + 0.75` and uses small rate steps for gentle movement.

## `.speedUp`

Speed-up mode is a threshold and hysteresis algorithm. It enters silence after consecutive buffers below the enter threshold and exits after buffers above the louder exit threshold.

When silent, it targets a fixed accelerated rate of `2.5x`. When speech returns, it targets `baseRate`. Attack and release use different smoothing and step limits, so acceleration can engage quickly while returning to normal speed more gradually.

## `.adaptiveSpeed`

Adaptive speed mode avoids fixed silence thresholds. It keeps a rolling loudness window, calculates quiet and speech reference percentiles, then maps the current loudness into a silence score.

The score has:

- A minimum dynamic range so low-contrast content remains stable.
- A dead zone so small loudness changes do not affect rate.
- A curve that makes subtle quietness produce little boost and stronger quietness produce more boost.

The final target is `baseRate + boost`, capped at `baseRate + 0.55`, with conservative smoothing and small step limits.

## Saved Time

When a silence mode runs faster than `baseRate`, the engine estimates saved time from the tap buffer frame length and current sample rate. Saved time is reported through:

- `SomeplayerEngineDelegate.playerEngine(_:savedSeconds:)`
- `PlayerEvent.savedSecondsUpdated`

Consumers can accumulate these values for a session total.
