import Foundation

public struct SomePlaybackTimeFormatter {
    public init() {}

    public func string(from interval: TimeInterval) -> String {
        if interval >= 60 * 60 {
            return hoursMinutesSeconds(from: interval)
        }
        let ts = Int(interval)
        let s  = ts % 60
        let m  = (ts / 60) % 60
        return String(format: "%02d:%02d", m, s)
    }

    public func hoursMinutesSeconds(from interval: TimeInterval) -> String {
        let ts = Int(interval)
        let s  = ts % 60
        let m  = (ts / 60) % 60
        let h  = (ts / 60) / 60
        return String(format: "%02d:%02d:%02d", h, m, s)
    }

    public static func string(from interval: TimeInterval) -> String {
        SomePlaybackTimeFormatter().string(from: interval)
    }
}
