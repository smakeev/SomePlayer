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

    struct DownloadingPolicyOption: Identifiable {
        let policy: SomePlayerEngine.PlayerEngineDownloadingPolicy
        let title: String
        let detail: String

        var id: Int { policy.rawValue }
    }

    let streamURL = URL(string: "https://traffic.libsyn.com/secure/syntax/Syntax_-_899.mp3")!
    let downloadingPolicyOptions: [DownloadingPolicyOption] = [
        DownloadingPolicyOption(
            policy: .stream,
            title: "Stream",
            detail: "Play while downloading and restart from the seek position when range requests are available."
        ),
        DownloadingPolicyOption(
            policy: .progressiveDownload,
            title: "Progressive",
            detail: "Play while downloading and wait for the current download to reach far seek positions."
        ),
        DownloadingPolicyOption(
            policy: .predownload,
            title: "Predownload",
            detail: "Wait for full download before reporting ready."
        )
    ]

    @Published private(set) var state: SomePlayerEngine.PlayerEngineState = .undefined
    @Published private(set) var timeline = PlayerDemoViewModel.emptyTimeline
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

    private var player = SomePlayer()
    private var isDraggingSlider = false

    private static let emptyTimeline = SomePlaybackTimelineState(
        currentTime: 0,
        duration: 0,
        currentTimeText: "00:00",
        durationText: "00:00",
        sliderValue: 0,
        sliderMaximumValue: 1,
        downloadProgress: 0,
        offsetProgress: 0
    )

    init(platform: Platform) {
        super.init()
        print("[SomePlayerDebug][ViewModel] init platform=\(platform)")
        configureAudioSessionIfNeeded(platform: platform)
        configurePlayer()
    }

    deinit {
        player.removeRateObserver(withId: "swiftui-example")
        player.delegate = nil
    }

    var canPlay: Bool {
        state == .ready || state == .playing || state == .paused || state == .ended
    }

    var isPlaying: Bool {
        state == .playing
    }

    var canSeek: Bool {
        let result = canPlay && timeline.sliderMaximumValue > 1 && player.duration > 0
        if !result {
            print("[SomePlayerDebug][ViewModel] canSeek=false state=\(state) max=\(timeline.sliderMaximumValue) duration=\(player.duration) range=\(player.rangeHeader) totalSize=\(player.totalSize)")
        }
        return result
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

    var downloadingPolicyTitle: String {
        title(for: downloadingPolicy)
    }

    var downloadingPolicy: SomePlayerEngine.PlayerEngineDownloadingPolicy {
        player.downloadingPolicy
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

    func selectDownloadingPolicy(_ policy: SomePlayerEngine.PlayerEngineDownloadingPolicy) {
        guard policy != player.downloadingPolicy else { return }
        let oldPlayer = player
        oldPlayer.pause()
        oldPlayer.removeRateObserver(withId: "swiftui-example")
        oldPlayer.delegate = nil

        resetPlaybackUI(clearSilenceMode: false)
        player = SomePlayer(policy)
        configurePlayer()
    }

    func beginSeeking() {
        isDraggingSlider = true
        isSeeking = true
    }

    func updateSeekingValue(_ value: Float) {
        sliderValue = value
    }

    func commitSeek() {
        guard canSeek, timeline.sliderMaximumValue > 0 else {
            print("[SomePlayerDebug][ViewModel] commitSeek rejected restoring slider=\(timeline.sliderValue)")
            isDraggingSlider = false
            isSeeking = false
            sliderValue = timeline.sliderValue
            return
        }
        isDraggingSlider = false
        isSeeking = false
        let targetTime: TimeInterval
        if player.rangeHeader {
            let percent = min(max(sliderValue / timeline.sliderMaximumValue, 0), 1)
            targetTime = TimeInterval(percent) * player.duration
            print("[SomePlayerDebug][ViewModel] commitSeek percent path percent=\(percent) targetTime=\(targetTime)")
            player.seekPercently(to: percent)
        } else {
            targetTime = TimeInterval(sliderValue)
            print("[SomePlayerDebug][ViewModel] commitSeek time path targetTime=\(targetTime)")
            player.seek(to: targetTime)
        }
    }

    func resetRate() {
        baseRate = 1
    }

    func resetPitch() {
        pitch = 0
    }

    func reload() {
        resetPlaybackUI(clearSilenceMode: true)
        player.reset()
    }

    private func resetPlaybackUI(clearSilenceMode: Bool) {
        state = .initializing
        timeline = Self.emptyTimeline
        sliderValue = 0
        isDraggingSlider = false
        isSeeking = false
        appliedRate = 1
        savedSeconds = 0
        errorMessage = nil
        title = "Loading stream..."
        artist = "Syntax"
        album = ""
        artwork = nil
        if clearSilenceMode {
            selectedMode = .none
        }
    }

    private func applyTimeline() {
        let latestTimeline = player.timelineState
        if isDraggingSlider {
            print("[SomePlayerDebug][ViewModel] applyTimeline SKIPPED isDragging=true isSeeking=\(isSeeking)")
            return
        }
        print("[SomePlayerDebug][ViewModel] applyTimeline UPDATE slider=\(latestTimeline.sliderValue) time=\(latestTimeline.currentTimeText) max=\(latestTimeline.sliderMaximumValue) isSeeking=\(isSeeking)")
        timeline = latestTimeline
        sliderValue = latestTimeline.sliderValue
    }

    private func configurePlayer() {
        print("[SomePlayerDebug][ViewModel] configurePlayer policy=\(downloadingPolicy) url=\(streamURL.absoluteString)")
        player.delegate = self
        player.baseRate = baseRate
        player.pitch = pitch
        player.globalGain = voiceBoost ? 10 : 0
        player.silenceHandlingType = selectedMode
        player.addRateObserver(withId: "swiftui-example") { [weak self] rate in
            Task { @MainActor in
                self?.appliedRate = rate
            }
        }
        player.openRemote(streamURL)
    }

    private func title(for policy: SomePlayerEngine.PlayerEngineDownloadingPolicy) -> String {
        downloadingPolicyOptions.first { $0.policy == policy }?.title ?? "Unknown"
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
        Task { @MainActor in
            guard playerEngine === self.player else { return }
            print("[SomePlayerDebug][ViewModelDelegate] download progress total=\(progress) task=\(currentProgress) offset=\(self.player.offset) hasBytes=\(self.player.hasBytes) totalSize=\(self.player.totalSize)")
            self.applyTimeline()
        }
    }

    nonisolated func playerEngine(_ playerEngine: SomePlayerEngine, changedState state: SomePlayerEngine.PlayerEngineState) {
        Task { @MainActor in
            guard playerEngine === self.player else { return }
            print("[SomePlayerDebug][ViewModelDelegate] state=\(state) current=\(self.timeline.currentTime) slider=\(self.sliderValue)")
            self.state = state
            self.applyTimeline()
        }
    }

    nonisolated func playerEngine(_ playerEngine: SomePlayerEngine, updatedCurrentTime currentTime: TimeInterval) {
        Task { @MainActor in
            guard playerEngine === self.player else { return }
            print("[SomePlayerDebug][ViewModelDelegate] currentTime=\(currentTime) sliderBefore=\(self.sliderValue) isSeeking=\(self.isSeeking)")
            self.applyTimeline()
        }
    }

    nonisolated func playerEngine(_ playerEngine: SomePlayerEngine, updatedDuration duration: TimeInterval) {
        Task { @MainActor in
            guard playerEngine === self.player else { return }
            print("[SomePlayerDebug][ViewModelDelegate] duration=\(duration) timelineMaxBefore=\(self.timeline.sliderMaximumValue)")
            self.applyTimeline()
        }
    }

    nonisolated func playerEngine(_ playerEngine: SomePlayerEngine, savedSeconds: TimeInterval) {
        Task { @MainActor in
            guard playerEngine === self.player else { return }
            self.savedSeconds += savedSeconds
        }
    }

    nonisolated func playerEngine(_ playerEngine: SomePlayerEngine, offsetChanged offset: Int64) {
        Task { @MainActor in
            guard playerEngine === self.player else { return }
            print("[SomePlayerDebug][ViewModelDelegate] offsetChanged offset=\(offset)")
            self.applyTimeline()
        }
    }

    nonisolated func playerEngine(_ playerEngine: SomePlayerEngine, changedImage image: SomePlayerImage) {
        Task { @MainActor in
            guard playerEngine === self.player else { return }
            self.artwork = image
        }
    }

    nonisolated func playerEngine(_ playerEngine: SomePlayerEngine, changedTitle title: String) {
        Task { @MainActor in
            guard playerEngine === self.player else { return }
            self.title = title
        }
    }

    nonisolated func playerEngine(_ playerEngine: SomePlayerEngine, changedArtist artist: String) {
        Task { @MainActor in
            guard playerEngine === self.player else { return }
            self.artist = artist
        }
    }

    nonisolated func playerEngine(_ playerEngine: SomePlayerEngine, changedAlbum album: String) {
        Task { @MainActor in
            guard playerEngine === self.player else { return }
            self.album = album
        }
    }

    nonisolated func playerEngine(_ playerEngine: SomePlayerEngine, isBuffering: Bool) {
        Task { @MainActor in
            guard playerEngine === self.player else { return }
            print("[SomePlayerDebug][ViewModelDelegate] buffering=\(isBuffering)")
            self.isBuffering = isBuffering
        }
    }

    nonisolated func playerEngine(_ playerEngine: SomePlayerEngine, isWaitingForDownloader: Bool) {
        Task { @MainActor in
            guard playerEngine === self.player else { return }
            print("[SomePlayerDebug][ViewModelDelegate] waitingForDownloader=\(isWaitingForDownloader)")
            self.isWaitingForDownloader = isWaitingForDownloader
        }
    }

    nonisolated func playerEngine(_ playerEngine: SomePlayerEngine, failedDownloadWithError error: Error, forURL url: URL) {
        Task { @MainActor in
            guard playerEngine === self.player else { return }
            self.errorMessage = error.localizedDescription
        }
    }

    nonisolated func playerEngine(_ playerEngine: SomePlayerEngine, failedWithException exception: SomePlayerEngine.FailureType) {
        Task { @MainActor in
            guard playerEngine === self.player else { return }
            self.errorMessage = "Player failed: \(exception)"
        }
    }
}
