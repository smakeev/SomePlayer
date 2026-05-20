import AVFoundation
import Foundation
import SomePlayer
import SwiftUI

#if canImport(UIKit)
import UIKit
#endif

@MainActor
final class PlayerDemoViewModel: NSObject, ObservableObject {
    enum Platform {
        case iOS
        case macOS
    }

    let streamURL = URL(string: "https://traffic.libsyn.com/secure/syntax/Syntax_-_899.mp3")!

    @Published private(set) var state: SomePlayerEngine.PlayerEngineState = .undefined
    @Published private(set) var timeline = SomePlaybackTimelineState(
        currentTime: 0,
        duration: 0,
        currentTimeText: "00:00",
        durationText: "00:00",
        sliderValue: 0,
        sliderMaximumValue: 1,
        downloadProgress: 0,
        offsetProgress: 0
    )
    @Published private(set) var appliedRate: Float = 1
    @Published private(set) var savedSeconds: TimeInterval = 0
    @Published private(set) var title: String = "Loading stream..."
    @Published private(set) var artist: String = "Syntax"
    @Published private(set) var album: String = ""
    @Published private(set) var artwork: SomePlayerImage?
    @Published private(set) var isBuffering = false
    @Published private(set) var isWaitingForDownloader = false
    @Published private(set) var errorMessage: String?

    @Published var baseRate: Float = 1 {
        didSet {
            let steppedRate = (baseRate * 10).rounded() / 10
            if steppedRate != baseRate {
                baseRate = steppedRate
                return
            }
            player.baseRate = steppedRate
        }
    }
    @Published var pitch: Float = 0 {
        didSet {
            let steppedPitch = (pitch / 100).rounded() * 100
            if steppedPitch != pitch {
                pitch = steppedPitch
                return
            }
            player.pitch = steppedPitch
        }
    }
    @Published var voiceBoost = false {
        didSet {
            player.globalGain = voiceBoost ? 10 : 0
        }
    }
    @Published var selectedMode: SomeSilenceSkippingMode = .none {
        didSet {
            player.silenceHandlingType = selectedMode
        }
    }
    @Published var sliderValue: Float = 0
    @Published var isSeeking = false

    let player = SomePlayer(.progressiveDownload)

    init(platform: Platform) {
        super.init()
        player.delegate = self
        configureAudioSessionIfNeeded(platform: platform)
        player.addRateObserver(withId: "swiftui-example") { [weak self] rate in
            Task { @MainActor in
                self?.appliedRate = rate
            }
        }
        player.openRemote(streamURL)
    }

    deinit {
        player.removeRateObserver(withId: "swiftui-example")
    }

    var canPlay: Bool {
        state == .ready || state == .playing || state == .paused || state == .ended
    }

    var isPlaying: Bool {
        state == .playing
    }

    var statusText: String {
        if isWaitingForDownloader {
            return "Waiting for data"
        }
        if isBuffering {
            return "Buffering"
        }
        switch state {
        case .undefined:
            return "Idle"
        case .initializing:
            return "Preparing"
        case .ready:
            return "Ready"
        case .playing:
            return "Playing"
        case .paused:
            return "Paused"
        case .ended:
            return "Ended"
        case .failed:
            return "Failed"
        }
    }

    var durationText: String {
        timeline.durationText
    }

    var currentTimeText: String {
        isSeeking ? SomePlaybackTimeFormatter.string(from: previewSeekTime) : timeline.currentTimeText
    }

    var savedSecondsText: String {
        SomePlaybackTimeFormatter.string(from: savedSeconds)
    }

    var downloadProgressText: String {
        "\(Int((timeline.downloadProgress * 100).rounded()))%"
    }

    var sampleRateText: String {
        guard let sampleRate = player.sampleRate else { return "unknown" }
        return "\(Int(sampleRate.rounded())) Hz"
    }

    var rangeHeaderText: String {
        player.rangeHeader ? "yes" : "no"
    }

    private var previewSeekTime: TimeInterval {
        guard timeline.sliderMaximumValue > 0 else { return 0 }
        if player.rangeHeader {
            let percent = sliderValue / timeline.sliderMaximumValue
            return TimeInterval(percent) * player.duration
        }
        return TimeInterval(sliderValue)
    }

    func togglePlayback() {
        if isPlaying {
            player.pause()
        } else {
            player.play()
        }
    }

    func toggleMode(_ mode: SomeSilenceSkippingMode) {
        selectedMode = selectedMode == mode ? .none : mode
    }

    func beginSeeking() {
        isSeeking = true
    }

    func updateSeekingValue(_ value: Float) {
        sliderValue = value
    }

    func commitSeek() {
        defer { isSeeking = false }
        guard timeline.sliderMaximumValue > 0 else { return }
        if player.rangeHeader {
            player.seekPercently(to: sliderValue / timeline.sliderMaximumValue)
        } else {
            player.seek(to: TimeInterval(sliderValue))
        }
    }

    func resetRate() {
        baseRate = 1
    }

    func resetPitch() {
        pitch = 0
    }

    func reload() {
        savedSeconds = 0
        errorMessage = nil
        title = "Loading stream..."
        artist = "Syntax"
        album = ""
        artwork = nil
        selectedMode = .none
        player.openRemote(streamURL)
    }

    private func applyTimeline() {
        timeline = player.timelineState
        if !isSeeking {
            sliderValue = timeline.sliderValue
        }
    }

    private func configureAudioSessionIfNeeded(platform: Platform) {
        #if canImport(UIKit)
        guard platform == .iOS else { return }
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .default, policy: .default, options: [.allowBluetoothA2DP, .defaultToSpeaker])
            try session.setActive(true)
        } catch {
            errorMessage = error.localizedDescription
        }
        #endif
    }
}

extension PlayerDemoViewModel: SomeplayerEngineDelegate {
    nonisolated func playerEngine(_ playerEngine: SomePlayerEngine, updatedDownloadProgress progress: Float, currentTaskProgress currentProgress: Float, forURL url: URL) {
        Task { @MainActor in self.applyTimeline() }
    }

    nonisolated func playerEngine(_ playerEngine: SomePlayerEngine, changedState state: SomePlayerEngine.PlayerEngineState) {
        Task { @MainActor in
            self.state = state
            self.applyTimeline()
        }
    }

    nonisolated func playerEngine(_ playerEngine: SomePlayerEngine, updatedCurrentTime currentTime: TimeInterval) {
        Task { @MainActor in self.applyTimeline() }
    }

    nonisolated func playerEngine(_ playerEngine: SomePlayerEngine, updatedDuration duration: TimeInterval) {
        Task { @MainActor in self.applyTimeline() }
    }

    nonisolated func playerEngine(_ playerEngine: SomePlayerEngine, savedSeconds: TimeInterval) {
        Task { @MainActor in self.savedSeconds += savedSeconds }
    }

    nonisolated func playerEngine(_ playerEngine: SomePlayerEngine, offsetChanged offset: Int64) {
        Task { @MainActor in self.applyTimeline() }
    }

    nonisolated func playerEngine(_ playerEngine: SomePlayerEngine, changedImage image: SomePlayerImage) {
        Task { @MainActor in self.artwork = image }
    }

    nonisolated func playerEngine(_ playerEngine: SomePlayerEngine, changedTitle title: String) {
        Task { @MainActor in self.title = title }
    }

    nonisolated func playerEngine(_ playerEngine: SomePlayerEngine, changedArtist artist: String) {
        Task { @MainActor in self.artist = artist }
    }

    nonisolated func playerEngine(_ playerEngine: SomePlayerEngine, changedAlbum album: String) {
        Task { @MainActor in self.album = album }
    }

    nonisolated func playerEngine(_ playerEngine: SomePlayerEngine, isBuffering: Bool) {
        Task { @MainActor in self.isBuffering = isBuffering }
    }

    nonisolated func playerEngine(_ playerEngine: SomePlayerEngine, isWaitingForDownloader: Bool) {
        Task { @MainActor in self.isWaitingForDownloader = isWaitingForDownloader }
    }

    nonisolated func playerEngine(_ playerEngine: SomePlayerEngine, failedDownloadWithError error: Error, forURL url: URL) {
        Task { @MainActor in self.errorMessage = error.localizedDescription }
    }

    nonisolated func playerEngine(_ playerEngine: SomePlayerEngine, failedWithException exception: SomePlayerEngine.FailureType) {
        Task { @MainActor in self.errorMessage = "Player failed: \(exception)" }
    }
}
