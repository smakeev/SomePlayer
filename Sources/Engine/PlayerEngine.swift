//
//  PlayerEngine.swift
//  AudioStreamer
//
//  Created by Sergey Makeev on 29/05/2019.
//

import Foundation
@preconcurrency import AVFoundation

#if canImport(UIKit)
import UIKit
public typealias SomePlayerImage = UIImage
#elseif canImport(AppKit)
import AppKit
public typealias SomePlayerImage = NSImage
#endif

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


/// `@unchecked Sendable`: mutation paths that cross threads now route
/// through `DelegateEmitter` (lock-protected, drained on `@MainActor`) or
/// the audio pipeline's serial executor. Remaining property mutations
/// happen on the caller's thread today and are scheduled to move onto
/// the audio executor in Phase 3's command-queue work — see THREADING_PLAN.md.
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

    public internal(set) var downloadingPolicy: PlayerEngineDownloadingPolicy

    public var volume: Float {
        get {
            return streamer.volume
        }
        set {
            streamer.volume = newValue
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
            silenceRateController.reset()
            if oldValue == .none {
                self.rate = self.baseRate
            } else {
                applySmartRate(self.rate, maxRate: max(self.rate, self.baseRate))
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
            for observer in isGoodForStreamObservers.values {
                observer(isGoodForStream)
            }
            emit(.isGoodForStreamChanged(isGoodForStream))
        }
    }
    fileprivate var isGoodForStreamObservers: [String : (Bool)->Void] = [String : (Bool)->Void]()
    public func addIsGoodForStreamObservers(withId id: String, observer: @escaping (Bool)->Void) {
        isGoodForStreamObservers[id] = observer
    }

    public func removeIsGoodForStreamObservers(withId id: String) {
        isGoodForStreamObservers[id] = nil
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
        guard !fileDownloaded else { return }
        if self.downloadingPolicy == .progressiveDownload {
            if let resumableData {
                print("[SomePlayerDebug][Engine] resume progressive using resumable offset=\(resumableData.offset) readyData=\(resumableData.readyData)")
                streamer.resume(resumableData)
            } else {
                print("[SomePlayerDebug][Engine] resume progressive from original url")
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
        resetPlaybackStateForOpening(isLocal: false, clearMetadata: true)
        handleMeta(url) {
            self.url = url
        }
    }

    public func openLocal(_  url: URL) {
        resetPlaybackStateForOpening(isLocal: true, clearMetadata: true)
        fileDownloaded = true
        handleMeta(url) {
            self.url = url
        }
    }

    /// Resets playback state and reloads the current item without replacing the player instance.
    public func reset() {
        guard let url else {
            resetPlaybackStateForOpening(isLocal: isLocal, clearMetadata: true)
            state = .undefined
            return
        }

        let shouldOpenLocal = isLocal
        resetPlaybackStateForOpening(isLocal: shouldOpenLocal, clearMetadata: true)
        if shouldOpenLocal {
            fileDownloaded = true
        }
        handleMeta(url) {
            self.url = url
        }
    }

    public func pause() {
        streamer.pause()
    }

    public func play() {
        if hasError {
            resume()
        }
        streamer.play()
    }

    public func seek(to time: TimeInterval) {
        do{
            silenceRateController.reset()
            self.rate = self.baseRate
            try streamer.seek(to: time)
        }
        catch {
            delegateEmitter.enqueueEdge(.seekFailed(error))
            emit(.seekFailed(error))
        }
    }

    public func seekPercently(to percent: Float) {
        silenceRateController.reset()
        self.rate = self.baseRate
        guard percent >= 0.0 && percent <= 1.0 else { return }
        if fileDownloaded {
            offset = 0
            let intervalToSeek = hasDuration * TimeInterval(percent)
            seek(to: intervalToSeek)
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
                    self.pause()
                    self.play()
                }
            }
            let percentWide = percentWeAre - percentOffset
            //let timeToSeek = (TimeInterval(percent) * hasDuration) / TimeInterval(percentWide)
            let hasWide = percent - percentOffset
            let realPercent = hasWide / percentWide
            let timeToSeek = TimeInterval(realPercent) * hasDuration
            seek(to: timeToSeek)
            return
        }

        if percent == 1 && downloadingPolicy != .progressiveDownload {
            offset = headerSize
            resumableData = nil
            try! self.streamer.seek(to: 0, internalUse: true)
            self.streamer.stop()
            self.state = .ended
            return
        }

        if !rangeHeader && downloadingPolicy == .stream {
            seek(to: hasDuration)
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
            print("[SomePlayerDebug][Engine] seekPercently range restart offset=\(offset) percent=\(percent) totalSizeWithoutHeader=\(totalSize) headerSize=\(headerSize)")
            streamer.progressiveSeek = 0
            streamer.waitForProgress = 0
            streamer.progressiveInPlay = false
            restart()
        } else if downloadingPolicy == .predownload {
            seek(to: 0) //we should not be here. Make sure seek is available only on .ready state.
        }
    }

    public func restart() {
        let stateBefore = streamer.state
        streamer.reset()
        resume()
        if stateBefore == .playing {
            play()
        }
    }

    public var globalGain: Float {
        get {
            return streamer.globalGain
        }

        set {
            silenceRateController.reset()
            self.rate = self.baseRate
            streamer.globalGain = newValue
        }
    }

    public var pitch: Float {
        get {
            return streamer.pitch
        }
        set {
            streamer.pitch = newValue
        }
    }

    public var baseRate: Float = 1.0 {
        didSet {
            self.rate = baseRate
        }
    }

    public internal(set) var rate: Float {
        get {
            return streamer.rate
        }
        set {
            streamer.rate = newValue
            for observer in rateObservers.values {
                observer(newValue)
            }
            emit(.rateChanged(newValue))
        }
    }

    fileprivate var rateObservers: [String : (Float)->Void] = [String : (Float)->Void]()
    public func addRateObserver(withId id: String, observer: @escaping (Float)->Void) {
        rateObservers[id] = observer
    }

    public func removeRateObserver(withId id: String) {
        rateObservers[id] = nil
    }

    private let smartRateMaxBoost: Float = 0.75
    private let smartRateMaxStep: Float = 0.04
    private let smartRateSmoothing: Float = 0.25
    private let smartRateSnapThreshold: Float = 0.001
    private var silenceRateController = SilenceRateController()

    private func applySmartRate(
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
        rate = abs(boundedTarget - nextRate) <= smartRateSnapThreshold ? boundedTarget : nextRate
    }

    private func handleSilence(loudness: Float? = nil, frameLength: AVAudioFrameCount? = nil) {

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

    public fileprivate(set) var averagePowerForChannel0: Float? = nil
    public fileprivate(set) var averagePowerForChannel1: Float? = nil

    public fileprivate(set) var lastBuffer: AVAudioPCMBuffer?
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
        DispatchQueue.main.async {
            self.averagePowerForChannel0 = powerLevels?.channel0
            self.averagePowerForChannel1 = powerLevels?.channel1
            self.handleSilence(loudness: powerLevels?.combined, frameLength: powerLevels?.frameLength)
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
                self.lastBuffer = buffer
                if let snapshot = AudioBufferSnapshot(from: buffer, sampleTime: when.sampleTime) {
                    self.emit(.audioBufferTap(snapshot))
                }
                self.handlePowerLevels(SilenceAudioAnalyzer.powerLevels(from: buffer))
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
