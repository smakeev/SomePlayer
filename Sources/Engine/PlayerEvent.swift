//
//  PlayerEvent.swift
//  SomePlayer
//
//  Public event stream payloads emitted by `SomePlayerEngine.subscribe()`.
//  See THREADING_PLAN.md for the broader context.
//

import Foundation
import AVFoundation

/// A `Sendable` snapshot of audio data captured from the engine's main-mixer tap.
/// Replaces direct exposure of `AVAudioPCMBuffer` (non-Sendable) across thread boundaries.
public struct AudioBufferSnapshot: Sendable {
    /// Per-channel float samples. Outer array is channel index, inner array is frames.
    public let samples: [[Float]]
    public let sampleRate: Double
    public let frameLength: AVAudioFrameCount
    public let sampleTime: AVAudioFramePosition?

    public init(
        samples: [[Float]],
        sampleRate: Double,
        frameLength: AVAudioFrameCount,
        sampleTime: AVAudioFramePosition?
    ) {
        self.samples = samples
        self.sampleRate = sampleRate
        self.frameLength = frameLength
        self.sampleTime = sampleTime
    }

    /// Convenience constructor that copies samples out of a live `AVAudioPCMBuffer`.
    /// Returns nil if the buffer has no float channel data.
    public init?(from buffer: AVAudioPCMBuffer, sampleTime: AVAudioFramePosition?) {
        guard let channelData = buffer.floatChannelData else { return nil }
        let channelCount = Int(buffer.format.channelCount)
        let frames = Int(buffer.frameLength)
        var samples: [[Float]] = []
        samples.reserveCapacity(channelCount)
        for channel in 0..<channelCount {
            let pointer = channelData[channel]
            samples.append(Array(UnsafeBufferPointer(start: pointer, count: frames)))
        }
        self.samples = samples
        self.sampleRate = buffer.format.sampleRate
        self.frameLength = buffer.frameLength
        self.sampleTime = sampleTime
    }
}

/// Every observable event emitted by `SomePlayerEngine`. Delivered at full rate via
/// the `AsyncStream` returned from `subscribe()`. The `@MainActor` delegate receives a
/// coalesced/throttled subset (see THREADING_PLAN.md §"Delegate throttling").
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
