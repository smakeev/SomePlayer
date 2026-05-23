//
//  Streamer.swift
//  AudioStreamer
//
//  Created by Syed Haris Ali on 6/5/18.
//

import AVFoundation
import Foundation
import os.log

/// The `Streamer` is a concrete implementation of the `Streaming` protocol and is intended to provide a high-level, extendable class for streaming an audio file living at a URL on the internet. Subclasses can override the `attachNodes` and `connectNodes` methods to insert custom effects.
///
/// `@unchecked Sendable`: internal state is only ever touched from the
/// `audioPipeline` actor's executor.
open class Streamer: Streaming, @unchecked Sendable {
    static let logger = OSLog(subsystem: "com.fastlearner.streamer", category: "Streamer")

    /// Hosts the audio-side long-running tasks (scheduling tick, volume
    /// ramp, downloader consumer) on a dedicated serial executor.
    public let audioPipeline = AudioPipeline()

    // MARK: - Properties (Streaming)

    public var currentTime: TimeInterval? {
        guard let nodeTime = playerEngineNode.lastRenderTime,
            let playerTime = playerEngineNode.playerTime(forNodeTime: nodeTime) else {
                return currentTimeOffset
        }

        if progressive && waitForProgress > 0 {
            return progressiveSeek
        }

        let currentTime = TimeInterval(playerTime.sampleTime) / playerTime.sampleRate
        return currentTime + currentTimeOffset
    }
    weak public var delegate: StreamingDelegate?
    public internal(set) var duration:        TimeInterval?
    public internal(set) var totalDuration:   TimeInterval = 0
    public internal(set) var totalTimeOffset: TimeInterval = 0

    public lazy var downloader: Downloading = Downloader()
    public internal(set) var parser: Parsing?
    public internal(set) var reader: Reading?
    public let engine = AVAudioEngine()
    public let playerEngineNode = AVAudioPlayerNode()
    public internal(set) var state: StreamingState = .stopped {
        didSet {
            if oldValue != state {
                self.delegate?.streamer(self, changedState: state)
            }
        }
    }

    public var isLocal: Bool = false

    public var url: URL? {
        didSet {
            reset()
            if !isLocal {
                if let url = url {
                    downloader.url = url
                    downloader.start()
                }
            } else {
                if let url = url {
                    audioFile = try? AVAudioFile(forReading: url)
                }
            }
        }
    }

    public var volume: Float {
        get {
            return engine.mainMixerNode.outputVolume
        }
        set {
            engine.mainMixerNode.outputVolume = newValue
        }
    }
    var volumeRampTargetValue:     Float?
    var succededInProgressiveSeek: Bool = false
    var progressiveInPlay:         Bool = false

    /// One-shot latch for `fileFinished`. Without it, `handleTimeUpdate`
    /// re-fires the delegate on every tick after the end condition is met,
    /// since `seek(to: 0)` + `pause()` don't immediately move `currentTime`
    /// back below `duration`. Cleared by a successful seek or reset.
    private var didFireFileFinished: Bool = false
    // MARK: - Properties

    var waitForProgress: Float = 0 {
        didSet {
            guard progressive else { return }
            isBuffering = false
            if waitForProgress == 0 {
                if progressiveSeek != 0 {
                    do {
                        defer {
                            if succededInProgressiveSeek == true {
                                progressiveSeek = 0
                                if progressiveInPlay && !playerEngineNode.isPlaying {
                                    playerEngineNode.play()
                                    progressiveInPlay = false
                                }
                            }
                            succededInProgressiveSeek = true
                        }
                        try seek(to: progressiveSeek)
                        succededInProgressiveSeek = true
                    }
                    catch {
                        succededInProgressiveSeek = false
                    }
                }
            } else {
                if progressiveInPlay == false && playerEngineNode.isPlaying {
                    progressiveInPlay = true
                    playerEngineNode.pause()
                }
            }
        }
    }
    var progressive: Bool = false
    var progressiveSeek: TimeInterval = 0 {
        didSet {
            if progressive == false {
                progressiveSeek = 0
            }
        }
    }

    /// A `TimeInterval` used to calculate the current play time relative to a seek operation.
    var currentTimeOffset: TimeInterval = 0

    /// A `Bool` indicating whether the file has been completely scheduled into the playerEngine node.
    var isFileSchedulingComplete = false
    var isBuffering = false {
        didSet {
            if oldValue != isBuffering {
                delegate?.streamer(self, isBuffering: isBuffering)
            }
        }
    }
    // MARK: - Lifecycle

    public init() {        
        // Setup the audio engine (attach nodes, connect stuff, etc). No playback yet.
        setupAudioEngine()
    }

    // MARK: - Setup

    func setupAudioEngine() {
        //os_log("%@ - %d", log: Streamer.logger, type: .debug, #function, #line)

        // Attach nodes
        attachNodes()

        // Node nodes
        connectNodes()

        // Prepare the engine
        engine.prepare()

        // Drive buffer scheduling + time-update ticks from a Task on the
        // audio pipeline's serial executor at ~100 Hz.
        let pipeline = audioPipeline
        Task { [weak self] in
            await pipeline.startScheduling(interval: .milliseconds(10)) { [weak self] in
                guard let streamer = self else { return false }
                if streamer.state != .stopped {
                    if !streamer.isLocal && streamer.progressiveSeek == 0 {
                        streamer.scheduleNextBuffer()
                    }
                    streamer.handleTimeUpdate()
                    streamer.notifyTimeUpdated()
                }
                return true
            }
        }

        // Consume the downloader's event stream on the audio executor so
        // parser/reader mutations all serialise on the same domain.
        let downloaderRef = downloader
        Task { [weak self] in
            await pipeline.run(.downloadConsumer) { [weak self] in
                for await event in downloaderRef.events {
                    if Task.isCancelled { return }
                    guard let streamer = self else { return }
                    streamer.handleDownloadEvent(event)
                }
            }
        }
    }

    /// Subclass can override this to attach additional nodes to the engine before it is prepared. Default implementation attaches the `playerEngineNode`. Subclass should call super or be sure to attach the playerEngineNode.
    open func attachNodes() {
        engine.attach(playerEngineNode)
    }

    /// Subclass can override this to make custom node connections in the engine before it is prepared. Default implementation connects the playerEngineNode to the mainMixerNode on the `AVAudioEngine` using the default `readFormat`. Subclass should use the `readFormat` property when connecting nodes.
    open func connectNodes() {
        engine.connect(playerEngineNode, to: engine.mainMixerNode, format: readFormat)
    }

    // MARK: - Reset

    deinit {
        // Fire-and-forget cancellation; the pipeline is captured strongly
        // so it outlives the deinit long enough for the cancellation to
        // propagate, after which it's released.
        let pipeline = audioPipeline
        Task { await pipeline.cancelAll() }
    }

    func reset() {
        //os_log("%@ - %d", log: Streamer.logger, type: .debug, #function, #line)

        // Reset the playback state
        stop()
        currentTimeOffset = 0
        duration = nil
        reader = nil
        isFileSchedulingComplete = false
        didFireFileFinished = false

        // Create a new parser
        do {
            parser = try Parser()
            parser?.formatObserver = { [weak self] format in
                guard let validSelf = self else { return }
                self?.delegate?.streamer(validSelf, willProvideFormat: format)
            }
        } catch {
            //os_log("Failed to create parser: %@", log: Streamer.logger, type: .error, error.localizedDescription)
            delegate?.streamerFailedToCreateParser(self)
        }
    }

    // MARK: - Methods

    public func resume(_ resumableData: ResumableData) {
        downloader.resume(resumableData)
    }

    public func play() {
        //os_log("%@ - %d", log: Streamer.logger, type: .debug, #function, #line)

        // Check we're not already playing
        guard !playerEngineNode.isPlaying else {
            return
        }

        if !engine.isRunning {
            do {
                try engine.start()
            } catch {
                //os_log("Failed to start engine: %@", log: Streamer.logger, type: .error, error.localizedDescription)
                delegate?.streamerFailedToStartEngine(self)
            }
        }

        // To make the volume change less harsh we mute the output volume
        let lastVolume = volumeRampTargetValue ?? volume
        volume = 0

        // Start playback on the playerEngine node
        if !isBuffering && !progressive {
            playerEngineNode.play()
        } else if progressive && !isBuffering {
            if progressiveSeek == 0 {
                playerEngineNode.play()
            } else {
                progressiveInPlay = true
            }
        }


        // After 250ms we restore the volume to where it was
        swellVolume(to: lastVolume)

        // Update the state
        state = .playing
    }

    public func pause() {
        //os_log("%@ - %d", log: Streamer.logger, type: .debug, #function, #line)

        // Pause the playerEngine node and the engine
        if !isBuffering && !progressive {
            if playerEngineNode.isPlaying {
                playerEngineNode.pause()
            }
        } else if progressive && !isBuffering {
            if progressiveSeek != 0 {
                progressiveInPlay = false
            } else {
                if playerEngineNode.isPlaying {
                    playerEngineNode.pause()
                }
            }
        }

        // Update the state
        state = .paused
    }

    public func stop() {
        //os_log("%@ - %d", log: Streamer.logger, type: .debug, #function, #line)

        // Stop the downloader, the playerEngine node, and the engine
        downloader.stop()
        playerEngineNode.stop()
        engine.stop()
        isBuffering = false
        isFileSchedulingComplete = false
        // Update the state
        state = .stopped
    }

    var seekFrame: AVAudioFramePosition = 0
    var currentPosition: AVAudioFramePosition = 0
    private func seekLocal(to time: TimeInterval) {
        guard let audioFile = audioFile else { return }
        didFireFileFinished = false
        let isPlaying = playerEngineNode.isPlaying
        let lastVolume = volumeRampTargetValue ?? volume
        seekFrame = AVAudioFramePosition(Float(time) * audioSampleRate)
        seekFrame = max(seekFrame, 0)
        seekFrame = min(seekFrame, audioLengthSamples)
        currentPosition = seekFrame
        playerEngineNode.stop()
        volume = 0

        if currentPosition < audioLengthSamples {
            currentTimeOffset = time
            isFileSchedulingComplete = false

            playerEngineNode.scheduleSegment(audioFile, startingFrame: seekFrame, frameCount: AVAudioFrameCount(audioLengthSamples - seekFrame), at: nil) { [weak self] in
                    self?.isFileSchedulingComplete = true
            }
        }

        if isPlaying {
            playerEngineNode.play()
        }

        // Update the current time
        delegate?.streamer(self, updatedCurrentTime: time)

        // After 250ms we restore the volume back to where it was
        swellVolume(to: lastVolume)
    }

    public func seek(to time: TimeInterval, internalUse: Bool = false) throws {
        //os_log("%@ - %d [%.1f]", log: Streamer.logger, type: .debug, #function, #line, time)

        if isLocal {
            seekLocal(to: time)
            return
        }

        // Make sure we have a valid parser and reader
        guard let parser = parser, let reader = reader else {
            return
        }
        didFireFileFinished = false

        // Get the proper time and packet offset for the seek operation
        guard let frameOffset = parser.frameOffset(forTime: time),
            let packetOffset = parser.packetOffset(forFrame: frameOffset) else {
                return
        }
        currentTimeOffset = time
        isFileSchedulingComplete = false

        // We need to store whether or not the playerEngine node is currently playing to properly resume playback after
        let isPlaying = playerEngineNode.isPlaying
        let lastVolume = volumeRampTargetValue ?? volume

        // Stop the playerEngine node to reset the time offset to 0
        playerEngineNode.stop()
        volume = 0

        // Perform the seek to the proper packet offset
        do {
            try reader.seek(packetOffset)
        } catch {
            //os_log("Failed to seek: %@", log: Streamer.logger, type: .error, error.localizedDescription)
            return
        }

        // If the playerEngine node was previous playing then resume playback
        if isPlaying {
            playerEngineNode.play()
        }

        // Update the current time
        delegate?.streamer(self, updatedCurrentTime: time)

        if internalUse {
            engine.mainMixerNode.outputVolume = lastVolume
        } else {
            // After 250ms we restore the volume back to where it was
            swellVolume(to: lastVolume)
        }
    }

    func swellVolume(to newVolume: Float, duration: TimeInterval = 0.5) {
        volumeRampTargetValue = newVolume
        // The incremental ramp only steps up; for a zero/negative target,
        // hard-snap — otherwise the step-interval division would underflow
        // and the loop could spin forever.
        guard newVolume > 0 else {
            volume = max(0, newVolume)
            volumeRampTargetValue = nil
            return
        }
        let pipeline = audioPipeline
        let halfDurationNanos = UInt64((duration / 2.0) * 1_000_000_000)
        // Ramp ~10 steps of 0.1 to reach `newVolume`; spread evenly across
        // the remaining half of `duration`.
        let stepNanos = max(UInt64(1_000_000),
                            UInt64((Double(duration) / 2.0 / Double(newVolume * 10)) * 1_000_000_000))
        Task {
            await pipeline.run(.volumeRamp) { [weak self] in
                try? await Task.sleep(nanoseconds: halfDurationNanos)
                while !Task.isCancelled {
                    guard let streamer = self else { return }
                    if streamer.volume != newVolume {
                        streamer.volume = min(newVolume, streamer.volume + 0.1)
                        try? await Task.sleep(nanoseconds: stepNanos)
                    } else {
                        streamer.volumeRampTargetValue = nil
                        return
                    }
                }
            }
        }
    }

    // MARK: - Scheduling Buffers
    //schedulefile for local file

    func openLocal(_ url: URL) {
        isLocal = true
        self.url = url
    }

    func openRemote(_ url: URL) {
        isLocal = false
        self.url = url
    }

    var format: AVAudioFormat?
    var audioSampleRate: Float = 0
    var audioLengthSeconds: Float = 0
    var audioLengthSamples: AVAudioFramePosition = 0
    var audioFile: AVAudioFile? {
        didSet {
            if let audioFile = audioFile {
                audioLengthSamples = audioFile.length
                format = audioFile.processingFormat
                audioSampleRate = Float(format?.sampleRate ?? 44100)
                audioLengthSeconds = Float(audioLengthSamples) / audioSampleRate
                scheduleFile()
                self.duration = TimeInterval(audioLengthSeconds)
                notifyDurationUpdate(self.duration!)
                notifyDownloadProgress(1.0, bytes: audioFile.length)
            }
        }
    }

    func scheduleFile() {
        guard !isFileSchedulingComplete else {
            return
        }
        guard let validAudioFile = audioFile else {
            return
        }

        playerEngineNode.scheduleFile(validAudioFile, at: nil) {  [weak self] in
            self?.isFileSchedulingComplete = true
        }
    }

    internal var downloadingState: DownloadingState = .notStarted

    private let packetsMaxToSchedule: Int = 100
    private var stoppedForBuffering = false
    private var lastSteppedPacket:    Int = 0 {
        didSet {
            if lastSteppedPacket == 0 && isBuffering {
                if stoppedForBuffering {
                    return
                }
                playerEngineNode.pause()
                stoppedForBuffering = true
            } else if stoppedForBuffering {
                stoppedForBuffering = false
                if state == .playing {
                    playerEngineNode.play()
                }
            }
        }
    }
    func scheduleNextBuffer() {
        guard let reader = reader else {
            //os_log("No reader yet...", log: Streamer.logger, type: .debug)
            isBuffering = true
            if !stoppedForBuffering {
                stoppedForBuffering = true
                if playerEngineNode.isPlaying {
                    playerEngineNode.pause()
                }
            }
            return
        }

        if isFileSchedulingComplete && downloadingState == .completed {
            return
        }

        if lastSteppedPacket > packetsMaxToSchedule {
            return
        }
        do {
            let nextScheduledBuffer = try reader.read(readBufferSize)
            isBuffering = false
            isFileSchedulingComplete = false
            lastSteppedPacket += 1
            // scheduleBuffer's completion fires on an internal AVAudio
            // thread (not the real-time render thread). Hop back onto the
            // audio pipeline so `lastSteppedPacket` and `reader.freeBuffer`
            // run in the same serial domain as `read(_:)`.
            let pipeline = audioPipeline
            playerEngineNode.scheduleBuffer(nextScheduledBuffer) { [weak self, reader] in
                Task {
                    await pipeline.perform { [weak self] in
                        guard let streamer = self else { return }
                        streamer.lastSteppedPacket -= 1
                        reader.freeBuffer()
                    }
                }
            }
        } catch ReaderError.reachedEndOfFile {
            //os_log("Scheduler reached end of file", log: Streamer.logger, type: .debug)
            if downloadingState == .completed {
                isFileSchedulingComplete = true
            } else if downloadingState == .completedWithError {
                isBuffering = true
            }

        } catch ReaderError.notEnoughData {
            //os_log("Scheduler reached end of parsed part", log: Streamer.logger, type: .debug)
            isBuffering = true
        } catch {
            //os_log("Cannot schedule buffer: %@", log: Streamer.logger, type: .debug, error.localizedDescription)
            delegate?.streamerFailedToScheduleBuffer(self)
        }
    }

    // MARK: - Handling Time Updates

    /// Handles the duration value, explicitly checking if the duration is greater than the current value. For indeterminate streams we can accurately estimate the duration using the number of packets parsed and multiplying that by the number of frames per packet.
    func handleDurationUpdate() {
        if let newDuration = parser?.duration {
            // Check if the duration is either nil or if it is greater than the previous duration
            var shouldUpdate = false
            if duration == nil {
                shouldUpdate = true
            } else if let oldDuration = duration, oldDuration < newDuration {
                shouldUpdate = true
            }

            // Update the duration value
            if shouldUpdate {
                self.duration = newDuration
                notifyDurationUpdate(newDuration)
            }
        }
    }

    /// Handles the current time relative to the duration to make sure current time does not exceed the duration
    func handleTimeUpdate() {
        guard let currentTime = currentTime else {
            return
        }
        guard let duration = self.duration else { return }

        if currentTime + totalTimeOffset >= max(duration, totalDuration) {
            guard !didFireFileFinished else { return }
            didFireFileFinished = true
            try? seek(to: 0)
            pause()
            if let url = self.url {
                self.delegate?.streamer(self, fileFinished: url)
            }
        }
    }

    // MARK: - Notifying The Delegate

    func notifyDownloadProgress(_ progress: Float, bytes: Int64) {
        guard let url = url else {
            return
        }

        delegate?.streamer(self, updatedDownloadProgress: progress, bytesReceived: bytes, forURL: url)
    }

    func notifyDurationUpdate(_ duration: TimeInterval) {
        guard let _ = url else {
            return
        }

        delegate?.streamer(self, updatedDuration: duration)
    }

    func notifyTimeUpdated() {
        guard engine.isRunning, state == .playing else {
            return
        }

        guard let currentTime = currentTime else {
            return
        }

        delegate?.streamer(self, updatedCurrentTime: currentTime)
    }
}
