import Foundation

public struct SomePlayerItem: Equatable {
    public let url: URL
    public let title: String?

    public init(url: URL, title: String? = nil) {
        self.url = url
        self.title = title
    }
}
