import Foundation

public struct SomePlaybackTimelineState: Equatable {
    public let currentTime: TimeInterval
    public let duration: TimeInterval
    public let currentTimeText: String
    public let durationText: String
    public let sliderValue: Float
    public let sliderMaximumValue: Float
    public let downloadProgress: Float
    public let offsetProgress: Float

    public init(
        currentTime: TimeInterval,
        duration: TimeInterval,
        currentTimeText: String,
        durationText: String,
        sliderValue: Float,
        sliderMaximumValue: Float,
        downloadProgress: Float,
        offsetProgress: Float
    ) {
        self.currentTime = currentTime
        self.duration = duration
        self.currentTimeText = currentTimeText
        self.durationText = durationText
        self.sliderValue = sliderValue
        self.sliderMaximumValue = sliderMaximumValue
        self.downloadProgress = downloadProgress
        self.offsetProgress = offsetProgress
    }
}
