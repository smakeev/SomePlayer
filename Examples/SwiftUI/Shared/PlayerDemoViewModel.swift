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

    // Guards against the user-pref @Published setters re-pushing to the
    // engine when the assignment originated from an engine event (which
    // would otherwise spin: setter → engine → event → setter).
    @Published var baseRate: Float = 1 {
        didSet {
            let steppedRate = (baseRate * 10).rounded() / 10
            if steppedRate != baseRate {
                baseRate = steppedRate
                return
            }
            guard steppedRate != player.baseRate else { return }
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
            guard steppedPitch != player.pitch else { return }
            player.pitch = steppedPitch
        }
    }
    @Published var voiceBoost = false {
        didSet {
            let gain: Float = voiceBoost ? 10 : 0
            guard gain != player.globalGain else { return }
            player.globalGain = gain
        }
    }
    @Published var selectedMode: SomeSilenceSkippingMode = .none {
        didSet {
            guard selectedMode != player.silenceHandlingType else { return }
            player.silenceHandlingType = selectedMode
        }
    }
    @Published var sliderValue: Float = 0
    @Published var isSeeking = false

    /// Debug-only download-throttle slider value (ms). Pushed to the engine
    /// on change. Surfaced in the UI under `#if DEBUG` only; the engine API
    /// itself is always available.
    @Published var simulatedDownloadDelayMs: Double = 0 {
        didSet {
            let clamped = max(0, min(simulatedDownloadDelayMs, 5000))
            if clamped != simulatedDownloadDelayMs {
                simulatedDownloadDelayMs = clamped
                return
            }
            player.simulatedDownloadChunkDelayMilliseconds = UInt(clamped)
        }
    }

    private var player = SomePlayer()
    private var isDraggingSlider = false

    /// Use this for any consumer that needs every engine event in order, on
    /// the audio executor's cadence, without going through the throttled
    /// MainActor delegate. Common cases: analytics, debug logging, custom
    /// derived state. The stream finishes automatically when the engine
    /// deallocates. For typical UI binding (state, time, progress) prefer
    /// the `@MainActor` delegate — it's coalesced to ~10 Hz.
    ///
    /// Example:
    ///   Task {
    ///       for await event in engine.subscribe() {
    ///           print("[Engine event]", event)
    ///       }
    ///   }
    private var eventSubscription: Task<Void, Never>?

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
        eventSubscription?.cancel()
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
        eventSubscription?.cancel()
        eventSubscription = nil
        oldPlayer.delegate = nil

        // The new engine starts at defaults; its first delegate-set +
        // subscribe() replays will push all current values back into the
        // UI bindings, so the VM doesn't have to reset its own state.
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
        // Engine `reset()` puts every value back to its default; the
        // delegate replays those defaults, which flows back into the
        // @Published bindings. UI follows automatically — no manual
        // resetPlaybackUI needed.
        player.reset()
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
        player.simulatedDownloadChunkDelayMilliseconds = UInt(simulatedDownloadDelayMs)

        // Subscribe to the full-rate event stream and hop to MainActor for
        // SwiftUI-bound state. The throttled @MainActor delegate covers the
        // bulk of the playback events (state/time/duration/etc.); this
        // stream covers the user-pref settings that aren't part of the
        // delegate API, so the UI binds them back to engine state — for
        // example, after `player.reset()`.
        eventSubscription?.cancel()
        let events = player.subscribe()
        eventSubscription = Task { [weak self] in
            for await event in events {
                if Task.isCancelled { return }
                await MainActor.run { self?.applyEvent(event) }
            }
        }

        player.openRemote(streamURL)
    }

    /// Handle events coming off the engine's full-rate stream. Used for the
    /// settings that the throttled delegate doesn't cover, plus the live
    /// applied-rate signal. Updates @Published values via the setters that
    /// guard against echo (see `baseRate.didSet` etc.).
    private func applyEvent(_ event: PlayerEvent) {
        switch event {
        case .rateChanged(let value):
            appliedRate = value
        case .baseRateChanged(let value):
            baseRate = value
        case .pitchChanged(let value):
            pitch = value
        case .globalGainChanged(let value):
            voiceBoost = value > 0
        case .silenceHandlingTypeChanged(let mode):
            selectedMode = mode
        case .stateChanged(let newState):
            // .initializing is the engine's "I just reset" signal. Clear
            // the UI-only state (accumulator, error banner, drag flags)
            // that nothing else can clear for us.
            if newState == .initializing {
                savedSeconds = 0
                errorMessage = nil
                isDraggingSlider = false
                isSeeking = false
                sliderValue = 0
            }
        default:
            break
        }
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
