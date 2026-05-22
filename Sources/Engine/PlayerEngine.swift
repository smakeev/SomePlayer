//
//  PlayerEngine.swift
//  AudioStreamer
//
//  Created by Sergey Makeev on 29/05/2019.
//

import Foundation
import os
@preconcurrency import AVFoundation

#if canImport(UIKit)
import UIKit
public typealias SomePlayerImage = UIImage
#elseif canImport(AppKit)
import AppKit
public typealias SomePlayerImage = NSImage
#endif

@MainActor
public protocol SomeplayerEngineDelegate: AnyObject {
    func playerEngine(_ playerEngine: SomePlayerEngine, updatedDownloadProgress progress: Float, currentTaskProgress currentProgress: Float, forURL url: URL)
    func playerEngine(_ playerEngine: SomePlayerEngine, changedState state: SomePlayerEngine.PlayerEngineState)
    func playerEngine(_ playerEngine: SomePlayerEngine, updatedCurrentTime currentTime: TimeInterval)
    func playerEngine(_ playerEngine: SomePlayerEngine, updatedDuration duration: TimeInterval)
    func playerEngine(_ playerEngine: SomePlayerEngine, savedSeconds: TimeInterval)
    func playerEngine(_ playerEngine: SomePlayerEngine, offsetChanged offset: Int64)
    func playerEngine(_ playerEngine: SomePlayerEngine, changedImage image: SomePlayerImage)
    func playerEngine(_ playerEngine: SomePlayerEngine, changedTitle title: String)
    func playerEngine(_ playerEngine: SomePlayerEngine, changedArtist artist: String)
    func playerEngine(_ playerEngine: SomePlayerEngine, changedAlbum album: String)
    func playerEngine(_ playerEngine: SomePlayerEngine, isBuffering: Bool)
    func playerEngine(_ playerEngine: SomePlayerEngine, isWaitingForDownloader: Bool)
    func playerEngine(_ playerEngine: SomePlayerEngine, failedDownloadWithError error: Error, forURL url: URL)
    func playerEngine(_ playerEngine: SomePlayerEngine, failedWithException exception: SomePlayerEngine.FailureType)
    func playerEngine(_ playerEngine: SomePlayerEngine, seekFailed error: Error)
}

public extension SomeplayerEngineDelegate {
    func playerEngine(_ playerEngine: SomePlayerEngine, seekFailed error: Error) {}
}


/// `@unchecked Sendable`: cross-thread mutation paths are funnelled through
/// either the lock-protected `DelegateEmitter` (drained on `@MainActor`) or
/// the audio pipeline's serial executor. Plain class storage carries the
/// remaining state under that discipline.
open class SomePlayerEngine: NSObject, @unchecked Sendable {

    public enum FailureType: Sendable {
        case engineStart
        case scheduleBuffer
        case createParser
    }

    public enum PlayerEngineState: Int, Sendable {
        case undefined    = 0
        case initializing
        case ready
        case playing
        case paused
        case ended
        case failed
    }

    public enum PlayerEngineDownloadingPolicy: Int, Sendable {
        case stream               = 0
        case predownload
        case progressiveDownload
    }

    public init(_ policy: PlayerEngineDownloadingPolicy = .stream) {
        downloadingPolicy = policy
        super.init()
        delegateEmitter.engine = self
        Task { @MainActor [delegateEmitter] in
            delegateEmitter.start()
        }
    }

    // MARK: - Command queue

    /// Lock-protected cache of most-recently-set scalar values so sync
    /// getters reflect the latest setter call even though the actual AVAudio
    /// mutation runs asynchronously on the audio executor.
    struct EngineSnapshot: Sendable {
        var rate: Float?
        var volume: Float?
        var pitch: Float?
        var globalGain: Float?
        var baseRate: Float?
        // Power-level readouts from the audio tap. Public read via getters.
        var averagePowerForChannel0: Float?
        var averagePowerForChannel1: Float?
        // Latest tap buffer snapshot (replaces the racey `lastBuffer` property).
        var lastBufferSnapshot: AudioBufferSnapshot?
    }
    private let stateSnapshot = OSAllocatedUnfairLock<EngineSnapshot>(initialState: EngineSnapshot())

    /// Fire-and-forget command enqueue. A new command of the same `kind`
    /// cancels any in-flight task with that key. Work runs on the audio
    /// pipeline's serial executor, so all bodies see a single thread.
    private func enqueue(_ kind: AudioPipeline.TaskKey, _ work: @escaping @Sendable () -> Void) {
        let pipeline = streamer.audioPipeline
        Task(priority: .userInitiated) {
            await pipeline.run(kind) {
                work()
            }
        }
    }

    /// Convenience for the "cancel pending commands, then enqueue" pattern
    /// used by `openRemote`/`openLocal`/`reset`. Internal long-running
    /// loops (scheduling/downloader-consumer/volume-ramp) are preserved —
    /// only public command tasks are cancelled.
    private func enqueueExclusive(_ kind: AudioPipeline.TaskKey, _ work: @escaping @Sendable () -> Void) {
        let pipeline = streamer.audioPipeline
        Task(priority: .userInitiated) {
            await pipeline.cancelPublicCommands()
            await pipeline.run(kind) {
                work()
            }
        }
    }

    public internal(set) var downloadingPolicy: PlayerEngineDownloadingPolicy

    /// Inserts a fixed sleep between each downloaded chunk before it reaches
    /// the engine. Default 0 (no throttling). Setting a non-zero value makes
    /// the engine perceive the download as that much slower per chunk.
    public var simulatedDownloadChunkDelayMilliseconds: UInt {
        get { streamer.downloader.simulatedChunkDelayMilliseconds }
        set { streamer.downloader.simulatedChunkDelayMilliseconds = newValue }
    }

    public var volume: Float {
        get {
            stateSnapshot.withLock { $0.volume } ?? streamer.volume
        }
        set {
            stateSnapshot.withLock { $0.volume = newValue }
            enqueue(.setVolume) { [weak self] in
                self?.streamer.volume = newValue
            }
        }
    }

    public enum SilenceHandlingType: Int {
        case none
        case smart
        case speedUp
        case adaptiveSpeed
    }

    public var silenceHandlingType: SilenceHandlingType = .none {
        didSet {
            guard oldValue != silenceHandlingType else { return }
            let wasNone = (oldValue == .none)
            let base = self.baseRate
            let currentRate = self.rate
            enqueue(.setSilenceHandling) { [weak self] in
                guard let self = self else { return }
                self.silenceRateController.reset()
                if wasNone {
                    self.setRateDirect(base)
                } else {
                    self.applySmartRate(currentRate, maxRate: max(currentRate, base))
                }
            }
        }
    }

    public internal(set) var fileDownloaded: Bool  = false {
        didSet {
            if fileDownloaded == true {
                resumableData = nil
                if downloadingPolicy == .predownload {
                    state = .ready
                }
            }
        }
    }

    public internal(set) var format: AVAudioFormat? {
        didSet {
            if isInitialized && format != nil {
                if self.state == .initializing && self.downloadingPolicy != .predownload {
                    self.state = .ready
                }
            }
        }
    }

    public internal(set) var isGoodForStream: Bool = false {
        didSet {
            emit(.isGoodForStreamChanged(isGoodForStream))
        }
    }

    public fileprivate(set) var state: PlayerEngineState = .undefined {
        didSet {
            if state != oldValue {
                // Edge-triggered: FIFO via the emitter — preserves ordering
                // of intermediate transitions instead of dropping them.
                delegateEmitter.enqueueEdge(.stateChanged(state))
                emit(.stateChanged(state))
            }

            if state == .initializing {
                streamer.totalDuration = 0
            }
        }
    }

	public internal(set) var currentTime: TimeInterval = 0

	public var formattedCurrentTime: String {
		SomePlaybackTimeFormatter.string(from: currentTime)
	}

	public var duration:         TimeInterval {
		get {
			return max(hasDuration, estimatedDuration)
		}
	}

	public var formattedDuration: String {
		SomePlaybackTimeFormatter.string(from: duration)
	}

	public var timelineState: SomePlaybackTimelineState {
		let maximumValue: Float
		let sliderValue: Float

		if fileDownloaded {
			if rangeHeader {
				maximumValue = Float(totalSize)
				if hasDuration > 0 {
					sliderValue = Float(currentTime / hasDuration) * Float(totalSize)
				} else {
					sliderValue = 0
				}
			} else {
				maximumValue = Float(duration)
				sliderValue = Float(currentTime)
			}
		} else if rangeHeader {
			maximumValue = Float(totalSize)
			if hasDuration > 0 {
				let currentPercentOfDownloadedData = Float((currentTime - timeOffset) / hasDuration)
				let currentByte = Float(hasBytes) * currentPercentOfDownloadedData
				sliderValue = Float(offset) + currentByte
			} else {
				sliderValue = Float(offset)
			}
		} else {
			maximumValue = Float(hasDuration)
			sliderValue = Float(currentTime - timeOffset)
		}

		let offsetProgress: Float
		if totalSize > 0 {
			offsetProgress = Float(offset) / Float(totalSize)
		} else {
			offsetProgress = 0
		}

		return SomePlaybackTimelineState(
			currentTime: currentTime,
			duration: duration,
			currentTimeText: formattedCurrentTime,
			durationText: formattedDuration,
			sliderValue: sliderValue,
			sliderMaximumValue: maximumValue,
			downloadProgress: lastDownloadProgress,
			offsetProgress: offsetProgress
		)
	}

    public internal(set) var hasDuration:       TimeInterval = 0 {
        didSet {

        }
    }
    public internal(set) var estimatedDuration: TimeInterval = 0 {
        didSet {
            delegateEmitter.enqueueDuration(self.duration)
            emit(.durationUpdated(self.duration))
        }
    }

    public internal(set) var insiderInfoDuration: TimeInterval = 0
    fileprivate var needsAsset = true

    public func noAssetNeeded(duration: TimeInterval) {
        self.insiderInfoDuration = duration
        if duration > 0 {
            needsAsset = false
        }
    }

    public internal(set) var rangeHeader:    Bool  = false {
        didSet {

        }
    }
    public internal(set) var totalSize:      Int64 = 0 {
        didSet {
            self.aboutBitrate = (Double(self.totalSize - self.headerSize) * 8) / self.duration
        }
    }
    public internal(set) var headerSize:     Int64 = 0
    public internal(set) var hasBytes:       Int64 = 0 {
        didSet {

            if hasBytes > totalSize {
                totalSize = hasBytes
            }
        }
    }

	public internal(set) var aboutBitrate: Double = 0 {
        didSet {

        }
    }
	public private(set) var lastDownloadProgress: Float = 0
    public internal(set) var offset: Int64 = 0 {
        didSet {
            resumableData = nil
            hasBytes = 0
            delegateEmitter.enqueueOffset(offset)
            emit(.offsetChanged(offset))
            if aboutBitrate != 0 && offset != 0 {
                timeOffset = Double((offset - headerSize) * 8) / aboutBitrate
            } else {
                timeOffset = 0
            }
            streamer.totalTimeOffset = timeOffset
        }
    }

    public internal(set) var timeOffset:     TimeInterval = 0 {
        didSet {
        }
    }

    public internal(set) var hasError:       Bool = false

    public fileprivate(set) var resumableData: ResumableData?

    public func resume() {
        enqueue(.resume) { [weak self] in
            self?.resumeDirect()
        }
    }

    /// Direct body of `resume`. Called from the audio executor — either as
    /// the enqueued task, or from another already-executor-side command
    /// (e.g., `restart`).
    private func resumeDirect() {
        guard !fileDownloaded else { return }
        if self.downloadingPolicy == .progressiveDownload {
            if let resumableData {
                streamer.resume(resumableData)
            } else {
                hasBytes = 0
                streamer.url = self.url
            }
            return
        }

        if resumableData == nil {
            //just start from the beginnig
            streamer.url = self.url
        } else {
            streamer.resume(resumableData!)
        }
    }

    public var sampleRate: Double? {
        get {
            return streamer.parser?.dataFormat?.sampleRate
        }
    }

    /// Throttled (~10 Hz) main-thread emitter that fans `delegate` calls out
    /// from any source thread. Exposed publicly so consumers can inject
    /// their own emitter (e.g., for tests); usually nothing to touch.
    public let delegateEmitter = DelegateEmitter()

    /// The delegate that receives throttled main-thread notifications.
    /// Writes propagate to the emitter so deliveries land on `@MainActor`.
    weak public var delegate: SomeplayerEngineDelegate? = nil {
        didSet {
            delegateEmitter.delegate = delegate
        }
    }

    // MARK: - Event subscribers

    private var eventContinuations: [UUID: AsyncStream<PlayerEvent>.Continuation] = [:]

    /// Returns a fresh `AsyncStream` of every engine event. Each call yields an
    /// independent stream — events emitted after subscription are delivered to the
    /// caller; nothing is replayed. All active streams are `finish()`-ed when the
    /// engine is deallocated.
    ///
    /// Use this for full-rate observation (analytics, debug logging, custom UI
    /// pipelines). For throttled `@MainActor` delivery, conform to
    /// `SomeplayerEngineDelegate`.
    public func subscribe() -> AsyncStream<PlayerEvent> {
        let id = UUID()
        return AsyncStream { continuation in
            self.eventContinuations[id] = continuation
            continuation.onTermination = { [weak self] _ in
                self?.eventContinuations[id] = nil
            }
        }
    }

    fileprivate func emit(_ event: PlayerEvent) {
        for continuation in eventContinuations.values {
            continuation.yield(event)
        }
    }

    deinit {
        for continuation in eventContinuations.values {
            continuation.finish()
        }
    }

    lazy public internal(set) var streamer: TimePitchStreamer = {
        let streamer = TimePitchStreamer()
        if self.downloadingPolicy == .progressiveDownload {
            streamer.progressive = true
        }
        streamer.delegate = self
        return streamer
    }()

    public var isLocal: Bool = false

    public internal(set) var url: URL? {
        get { return streamer.url }
        set {
            guard let validURL = newValue else { return }
            if !isLocal {
                streamer.openRemote(validURL)
            } else {
                streamer.openLocal(validURL)
            }
        }
    }

    public private(set) var title: String? {
        didSet {
            guard let validTitle = title else { return }
            delegateEmitter.enqueueTitle(validTitle)
            emit(.titleChanged(validTitle))
        }
    }
    public private(set) var artist: String? {
        didSet {
            guard let validArtist = artist else { return }
            delegateEmitter.enqueueArtist(validArtist)
            emit(.artistChanged(validArtist))
        }
    }
    public private(set) var album: String? {
        didSet {
            guard let validAlbum = album else { return }
            delegateEmitter.enqueueAlbum(validAlbum)
            emit(.albumChanged(validAlbum))
        }
    }
    public private(set) var image: SomePlayerImage? {
        didSet {
            guard let validImage = image else { return }
            delegateEmitter.enqueueImage(validImage)
            emit(.imageChanged(validImage))
        }
    }

    private var id3Parser: ID3Parser?
    private func handleMeta(_ url: URL, handler: @escaping @Sendable ()-> Void) {
        self.state = .initializing
        let assetNeeded = self.needsAsset
        DispatchQueue.global().async {
            if self.id3Parser != nil {
                self.id3Parser?.cancel()
            }
            self.id3Parser = ID3Parser(url)
            self.id3Parser?.needsAsset = assetNeeded
            self.id3Parser?.parse { asset, headerSize in

                if let asset = asset {

                    DispatchQueue.main.async {
                        if headerSize == nil {
                            self.isGoodForStream = false
                        } else {
                            self.isGoodForStream = true //but bitrate could be variable
                        }
                        self.headerSize = headerSize ?? 0
                    }
                    let availableMetaFormats = asset.availableMetadataFormats
                    for format in availableMetaFormats {
                        for item in asset.metadata(forFormat: format) {
                            if let commonKey = item.commonKey {

                                if commonKey.rawValue == "title" {
                                    DispatchQueue.main.async {
                                        self.title = item.value as? String
                                    }
                                    continue
                                }
                                if commonKey.rawValue == "artist" {
                                    DispatchQueue.main.async {
                                        self.artist = item.value as? String
                                    }
                                    continue
                                }
                                if commonKey.rawValue == "albumName" {
                                    DispatchQueue.main.async {
                                        self.album = item.value as? String
                                    }
                                    continue
                                }
                                if commonKey.rawValue == "artwork" {
                                    if let value = item.value {
                                        if let data = value as? Data {
                                            DispatchQueue.main.async {
                                                self.image = SomePlayerImage(data: data)
                                            }
                                        }
                                    }
                                    continue
                                }
                            }
                        }
                    }
                }
                DispatchQueue.main.async {
                    if let validAsset = asset {
                        self.estimatedDuration = TimeInterval(CMTimeGetSeconds(validAsset.duration))
                    } else {
                        self.estimatedDuration = self.insiderInfoDuration
                    }
                    self.streamer.totalDuration = self.estimatedDuration

                    self.isInitialized = true
                    handler()
                }
            }
        }
    }

    public internal(set) var isInitialized: Bool = false

    private func resetPlaybackStateForOpening(isLocal: Bool, clearMetadata: Bool) {
        let oldDelegate = delegate
        delegate = nil
        offset = 0
        needsAsset = true
        insiderInfoDuration = 0
        isInitialized = false
        format = nil
        self.isLocal = isLocal
        currentTime = 0
        hasDuration = 0
        estimatedDuration = 0
        totalSize = 0
        headerSize = 0
        hasBytes = 0
        aboutBitrate = 0
        lastDownloadProgress = 0
        fileDownloaded = false
        hasError = false
        rangeHeader = false
        isBuffering = false
        isWaitingForDownloader = false
        silenceRateController.reset()
        rate = baseRate
        streamer.reset()
        if clearMetadata {
            title = nil
            artist = nil
            album = nil
            image = nil
        }
        self.delegate = oldDelegate
    }

    public func openRemote(_ url: URL) {
        enqueueExclusive(.open) { [weak self] in
            guard let self = self else { return }
            self.resetPlaybackStateForOpening(isLocal: false, clearMetadata: true)
            self.handleMeta(url) { [weak self] in
                self?.url = url
            }
        }
    }

    public func openLocal(_  url: URL) {
        enqueueExclusive(.open) { [weak self] in
            guard let self = self else { return }
            self.resetPlaybackStateForOpening(isLocal: true, clearMetadata: true)
            self.fileDownloaded = true
            self.handleMeta(url) { [weak self] in
                self?.url = url
            }
        }
    }

    /// Resets playback state and reloads the current item without replacing the player instance.
    public func reset() {
        let currentURL = self.url
        let wasLocal = self.isLocal
        enqueueExclusive(.reset) { [weak self] in
            guard let self = self else { return }
            guard let url = currentURL else {
                self.resetPlaybackStateForOpening(isLocal: wasLocal, clearMetadata: true)
                self.state = .undefined
                return
            }
            self.resetPlaybackStateForOpening(isLocal: wasLocal, clearMetadata: true)
            if wasLocal {
                self.fileDownloaded = true
            }
            self.handleMeta(url) { [weak self] in
                self?.url = url
            }
        }
    }

    public func pause() {
        enqueue(.pause) { [weak self] in
            self?.streamer.pause()
        }
    }

    public func play() {
        enqueue(.play) { [weak self] in
            guard let self = self else { return }
            if self.hasError {
                self.resumeDirect()
            }
            self.streamer.play()
        }
    }

    public func seek(to time: TimeInterval) {
        enqueue(.seek) { [weak self] in
            self?.seekDirect(to: time)
        }
    }

    /// Direct seek body; runs on the audio executor. Called by the enqueued
    /// `.seek` task and by `seekPercentlyDirect` when it computes a target time.
    private func seekDirect(to time: TimeInterval) {
        silenceRateController.reset()
        stateSnapshot.withLock { $0.rate = self.baseRate }
        streamer.rate = self.baseRate
        do {
            try streamer.seek(to: time)
        } catch {
            delegateEmitter.enqueueEdge(.seekFailed(error))
            emit(.seekFailed(error))
        }
    }

    public func seekPercently(to percent: Float) {
        enqueue(.seek) { [weak self] in
            self?.seekPercentlyDirect(to: percent)
        }
    }

    /// Direct seekPercently body; runs on the audio executor.
    private func seekPercentlyDirect(to percent: Float) {
        silenceRateController.reset()
        stateSnapshot.withLock { $0.rate = self.baseRate }
        streamer.rate = self.baseRate
        guard percent >= 0.0 && percent <= 1.0 else { return }
        if fileDownloaded {
            offset = 0
            let intervalToSeek = hasDuration * TimeInterval(percent)
            seekDirect(to: intervalToSeek)
            return
        }

        //check if we in downloaded part
        let totalSize = self.totalSize - self.headerSize
        let weAreHere = offset + hasBytes
        let percentWeAre = Float(weAreHere) / Float(totalSize)
        let percentOffset = Float(offset) / Float(totalSize)
        if percent >= percentOffset &&
           percent <= percentWeAre {

            //We are inside downloaded area
            if downloadingPolicy == .progressiveDownload {
                streamer.progressiveSeek = 0
                streamer.waitForProgress = 0
                streamer.progressiveInPlay = false
                if self.state == .playing {
                    streamer.pause()
                    streamer.play()
                }
            }
            let percentWide = percentWeAre - percentOffset
            let hasWide = percent - percentOffset
            let realPercent = hasWide / percentWide
            let timeToSeek = TimeInterval(realPercent) * hasDuration
            seekDirect(to: timeToSeek)
            return
        }

        if percent == 1 && downloadingPolicy != .progressiveDownload {
            offset = headerSize
            resumableData = nil
            do {
                try streamer.seek(to: 0, internalUse: true)
            } catch {
                delegateEmitter.enqueueEdge(.seekFailed(error))
                emit(.seekFailed(error))
            }
            streamer.stop()
            self.state = .ended
            return
        }

        if !rangeHeader && downloadingPolicy == .stream {
            seekDirect(to: hasDuration)
            return
        }

        if downloadingPolicy == .progressiveDownload {
            let targetTime = TimeInterval(percent) * duration
            streamer.progressiveSeek = targetTime
            streamer.waitForProgress = percent
            if state == .paused {
                delegateEmitter.enqueueTime(targetTime)
                emit(.currentTimeUpdated(targetTime))
            }
        } else if downloadingPolicy == .stream {
            offset = Int64(Float(totalSize) * percent) + headerSize
            resumableData = ResumableData(offset: offset)
            streamer.progressiveSeek = 0
            streamer.waitForProgress = 0
            streamer.progressiveInPlay = false
            // Already on the audio executor — inline the restart body
            // instead of re-enqueueing.
            let stateBefore = streamer.state
            streamer.reset()
            resumeDirect()
            if stateBefore == .playing {
                streamer.play()
            }
        } else if downloadingPolicy == .predownload {
            seekDirect(to: 0)
        }
    }

    public func restart() {
        enqueue(.restart) { [weak self] in
            guard let self = self else { return }
            let stateBefore = self.streamer.state
            self.streamer.reset()
            self.resumeDirect()
            if stateBefore == .playing {
                self.streamer.play()
            }
        }
    }

    public var globalGain: Float {
        get {
            stateSnapshot.withLock { $0.globalGain } ?? streamer.globalGain
        }

        set {
            stateSnapshot.withLock { $0.globalGain = newValue }
            // globalGain implicitly resets silence handling and rate.
            let base = stateSnapshot.withLock { $0.baseRate ?? baseRate }
            stateSnapshot.withLock { $0.rate = base }
            emit(.rateChanged(base))
            enqueue(.setGlobalGain) { [weak self] in
                guard let self = self else { return }
                self.silenceRateController.reset()
                self.streamer.rate = base
                self.streamer.globalGain = newValue
            }
        }
    }

    public var pitch: Float {
        get {
            stateSnapshot.withLock { $0.pitch } ?? streamer.pitch
        }
        set {
            stateSnapshot.withLock { $0.pitch = newValue }
            enqueue(.setPitch) { [weak self] in
                self?.streamer.pitch = newValue
            }
        }
    }

    public var baseRate: Float = 1.0 {
        didSet {
            stateSnapshot.withLock { $0.baseRate = baseRate }
            self.rate = baseRate
        }
    }

    public internal(set) var rate: Float {
        get {
            stateSnapshot.withLock { $0.rate } ?? streamer.rate
        }
        set {
            stateSnapshot.withLock { $0.rate = newValue }
            emit(.rateChanged(newValue))
            enqueue(.setRate) { [weak self] in
                self?.streamer.rate = newValue
            }
        }
    }

    private let smartRateMaxBoost: Float = 0.75
    private let smartRateMaxStep: Float = 0.04
    private let smartRateSmoothing: Float = 0.25
    private let smartRateSnapThreshold: Float = 0.001
    private var silenceRateController = SilenceRateController()

    /// Direct rate mutation called from within audio-executor work bodies
    /// (e.g., `applySmartRate`, `handleSilenceDirect`). Skips the public
    /// `rate` setter's enqueue hop and updates snapshot + emit
    /// + streamer.rate inline on the current thread.
    fileprivate func setRateDirect(_ newValue: Float) {
        stateSnapshot.withLock { $0.rate = newValue }
        emit(.rateChanged(newValue))
        streamer.rate = newValue
    }

    /// Computes the next smart-rate step and writes it via `setRateDirect`.
    /// Must run on the audio executor — touches `silenceRateController`
    /// state and `streamer.rate`.
    fileprivate func applySmartRate(
        _ targetRate: Float,
        maxRate: Float? = nil,
        maxStep: Float? = nil,
        smoothing: Float? = nil
    ) {
        let upperRate = max(maxRate ?? baseRate + smartRateMaxBoost, baseRate)
        let boundedTarget = min(max(targetRate, baseRate), upperRate)
        let currentRate = rate.isFinite ? rate : baseRate
        let rateSmoothing = smoothing ?? smartRateSmoothing
        let rateMaxStep = maxStep ?? smartRateMaxStep
        let smoothedRate = currentRate + (boundedTarget - currentRate) * rateSmoothing
        let delta = min(max(smoothedRate - currentRate, -rateMaxStep), rateMaxStep)
        let nextRate = currentRate + delta
        let resolved = abs(boundedTarget - nextRate) <= smartRateSnapThreshold ? boundedTarget : nextRate
        setRateDirect(resolved)
    }

    /// Silence-handling body. Renamed from `handleSilence` to make it
    /// explicit that it must run on the audio executor (called from the
    /// `.tapPower` task and the `.setSilenceHandling` task).
    fileprivate func handleSilenceDirect(loudness: Float? = nil, frameLength: AVAudioFrameCount? = nil) {

        func informForsavedTime() {
            if let validSampleRate = self.sampleRate {
                let frames = frameLength ?? streamer.readBufferSize
                let interval: Double = Double(frames) / validSampleRate
                let savedSeconds: Double = Double(interval - (interval / Double(self.rate)))
                self.delegateEmitter.enqueueSavedSeconds(savedSeconds)
                self.emit(.savedSecondsUpdated(savedSeconds))
            }
        }

        guard let decision = silenceRateController.decision(
            for: silenceRateControllerMode,
            loudness: loudness,
            baseRate: baseRate,
            globalGain: globalGain
        ) else {
            return
        }

        applySmartRate(
            decision.targetRate,
            maxRate: decision.maxRate,
            maxStep: decision.maxStep,
            smoothing: decision.smoothing
        )
        if decision.shouldReportSavedTime || rate > baseRate {
            informForsavedTime()
        }
    }

    private var silenceRateControllerMode: SilenceRateController.Mode {
        switch silenceHandlingType {
        case .none:
            return .none
        case .smart:
            return .smart
        case .speedUp:
            return .speedUp
        case .adaptiveSpeed:
            return .adaptiveSpeed
        }
    }

    /// Latest RMS power for channel 0 (decibels), captured by the main-mixer
    /// tap. Lock-protected snapshot — safe to read from any thread.
    public var averagePowerForChannel0: Float? {
        stateSnapshot.withLock { $0.averagePowerForChannel0 }
    }

    /// Latest RMS power for channel 1 (decibels), captured by the main-mixer
    /// tap. Lock-protected snapshot — safe to read from any thread.
    public var averagePowerForChannel1: Float? {
        stateSnapshot.withLock { $0.averagePowerForChannel1 }
    }

    /// Sendable copy of the most recent main-mixer tap buffer.
    /// Lock-protected snapshot — safe to read from any thread.
    public var lastBufferSnapshot: AudioBufferSnapshot? {
        stateSnapshot.withLock { $0.lastBufferSnapshot }
    }

    public fileprivate(set) var isBuffering: Bool = false

    //is only valid in case of progressiveDownloading mode.
    public fileprivate(set) var isWaitingForDownloader: Bool = false
}

extension SomePlayerEngine: StreamingDelegate {

    public func streamer(_ streamer: Streaming, isWaitingDownloader waiting: Bool) {
        isWaitingForDownloader = waiting
        delegateEmitter.enqueueWaitingForDownloader(waiting)
        emit(.waitingForDownloaderChanged(waiting))
    }

    public func streamer(_ streamer: Streaming, isBuffering: Bool) {
        self.isBuffering = isBuffering
        delegateEmitter.enqueueBuffering(isBuffering)
        emit(.bufferingChanged(isBuffering))
    }

    public func streamer(_ streamer: Streaming, fileFinished url: URL) {
        self.currentTime = timeOffset
        self.state = .ended
    }

    private func handlePowerLevels(_ powerLevels: SilencePowerLevels?) {
        // Silence-rate processing touches `silenceRateController` and the
        // rate setter chain — must run on the audio executor.
        enqueue(.tapPower) { [weak self] in
            self?.handleSilenceDirect(
                loudness: powerLevels?.combined,
                frameLength: powerLevels?.frameLength
            )
        }
    }

    public func streamer(_ streamer: Streaming, hasRangeHeader: Bool, totalSize: Int64) {
        if self.totalSize < totalSize {
            self.totalSize = totalSize
        }
        self.rangeHeader = hasRangeHeader
    }

    public func streamer(_ streamer: Streaming, failedDownloadWithError error: Error, forURL url: URL, readyData bytes: Int64, response: URLResponse) {
        hasError = true
        resumableData = ResumableData(offset: offset, response: response, readyData: bytes)
        delegateEmitter.enqueueEdge(.downloadFailed(error: error, url: url))
        emit(.downloadFailed(error: error, url: url))
    }

    public func streamer(_ streamer: Streaming, updatedDownloadProgress progress: Float, bytesReceived bytes: Int64, forURL url: URL) {
        hasError = false
        hasBytes += bytes
        if progress == 1.0 && (offset == 0 || offset == headerSize){
            fileDownloaded = true
        }

		//if server does not provide total size we can't get right progress.
		if progress >= 0 && totalSize > 0 {
			let totalProgress = Float(hasBytes) / Float(totalSize)
			lastDownloadProgress = totalProgress
			delegateEmitter.enqueueDownloadProgress(progress: totalProgress, taskProgress: progress, url: url)
			emit(.downloadProgressUpdated(progress: totalProgress, taskProgress: progress, url: url))
		}
        delegateEmitter.enqueueDuration(duration)
        emit(.durationUpdated(duration))
    }

    public func streamer(_ streamer: Streaming, changedState state: StreamingState) {
        silenceRateController.reset()
        self.rate = self.baseRate
        switch state {
        case .paused:
            self.state = .paused
        case .playing:
            self.state = .playing
        case .stopped:
            if isInitialized && format != nil && self.downloadingPolicy != .predownload {
                self.state = .ready
            }
        }
        let mainMixer = streamer.engine.mainMixerNode
        if state == .playing {
            let bufferSize = streamer.readBufferSize
            let format = mainMixer.outputFormat(forBus: 0)
            //print(format)

            mainMixer.installTap(onBus: 0, bufferSize: bufferSize, format: format) { buffer, when in
                let snapshot = AudioBufferSnapshot(from: buffer, sampleTime: when.sampleTime)
                let powerLevels = SilenceAudioAnalyzer.powerLevels(from: buffer)

                // Snapshot writes are lock-protected — safe inline from the
                // tap thread. AsyncStream yield is also thread-safe.
                self.stateSnapshot.withLock {
                    $0.lastBufferSnapshot = snapshot
                    $0.averagePowerForChannel0 = powerLevels?.channel0
                    $0.averagePowerForChannel1 = powerLevels?.channel1
                }
                if let snapshot = snapshot {
                    self.emit(.audioBufferTap(snapshot))
                }
                // Silence/rate state lives on the audio executor.
                self.handlePowerLevels(powerLevels)
            }

        } else {

            mainMixer.removeTap(onBus: 0)

        }
    }

    public func streamer(_ streamer: Streaming, updatedCurrentTime currentTime: TimeInterval) {
        self.currentTime = currentTime + self.timeOffset
        delegateEmitter.enqueueTime(currentTime)
        emit(.currentTimeUpdated(currentTime))
    }

    public func streamer(_ streamer: Streaming, updatedDuration duration: TimeInterval) {
        hasDuration = duration
        delegateEmitter.enqueueDuration(self.duration)
        emit(.durationUpdated(self.duration))
    }

    public func streamer(_ streamer: Streaming, willProvideFormat format: AVAudioFormat?) {
        self.format = format
    }

    public func streamerFailedToStartEngine(_ streamer: Streaming) {
        delegateEmitter.enqueueEdge(.failure(.engineStart))
        emit(.failure(.engineStart))
        self.state = .failed
    }

    public func streamerFailedToScheduleBuffer(_ streamer: Streaming) {
        delegateEmitter.enqueueEdge(.failure(.scheduleBuffer))
        emit(.failure(.scheduleBuffer))
        self.state = .failed
    }

    public func streamerFailedToCreateParser(_ streamer: Streaming) {
        delegateEmitter.enqueueEdge(.failure(.createParser))
        emit(.failure(.createParser))
        self.state = .failed
    }

}
