//
//  Downloader.swift
//  AudioStreamer
//
//  Created by Syed Haris Ali on 1/6/18.
//

import Foundation
import os.log

/// The `Downloader` is a concrete implementation of the `Downloading` protocol
/// using `URLSession` as the backing HTTP/HTTPS implementation.
///
/// `@unchecked Sendable`: state is mutated from URLSession's delegate queue
/// (a serial background queue) and read from the consuming `for await`
/// loop on the audio executor. There is no concurrent write path; the
/// AsyncStream serialises delivery to consumers.
public class Downloader: NSObject, Downloading, @unchecked Sendable {

    override init() {
        let (stream, continuation) = AsyncStream<DownloadEvent>.makeStream()
        self.events = stream
        self.eventsContinuation = continuation
        super.init()
        session = URLSession(configuration: .default, delegate: self, delegateQueue: nil)
    }

    static let logger = OSLog(subsystem: "com.fastlearner.streamer", category: "Downloader")

    // MARK: - Singleton

    /// A shared instance for clients that want to reuse one downloader (and
    /// the shared URL cache) across multiple requests.
    nonisolated(unsafe) public static var shared: Downloader = Downloader()

    // MARK: - Properties

    /// A `Bool` indicating whether the session should use the shared URL cache or not. Really useful for testing, but in production environments you probably always want this to `true`. Default is true.
    public var useCache = true {
        didSet {
            session?.configuration.urlCache = useCache ? URLCache.shared : nil
        }
    }

    /// The `URLSession` currently being used as the HTTP/HTTPS implementation for the downloader.
    internal var session: URLSession?

    /// A `URLSessionDataTask` representing the data operation for the current `URL`.
    internal var task: URLSessionDataTask?

    /// A `Int64` representing the total amount of bytes received
    var totalBytesReceived: Int64 = 0

    /// A `Int64` representing the total amount of bytes for the entire file
    var totalBytesCount: Int64 = 0

    // MARK: - Properties (Downloading)

    public let events: AsyncStream<DownloadEvent>
    internal let eventsContinuation: AsyncStream<DownloadEvent>.Continuation

    public var completionHandler: ((Error?) -> Void)?
    public var progressHandler: ((Data, Float) -> Void)?
    public var progress: Float = 0

    /// See `Downloading.simulatedChunkDelayMilliseconds`. Applied inside the
    /// URLSession data callback; the sleep happens on the session's delegate
    /// queue so subsequent chunks are paced accordingly.
    public var simulatedChunkDelayMilliseconds: UInt = 0
    public var state: DownloadingState = .notStarted {
        didSet {
            eventsContinuation.yield(.stateChanged(state))
        }
    }
    public var url: URL? {
        didSet {
            if state == .started {
                stop()
            }

            if let url = url {
                progress = 0.0
                state = .notStarted
                totalBytesCount = 0
                totalBytesReceived = 0
                let request = URLRequest(url: url)
                //todo add headers if needed
                if let session = session {
                    task = session.dataTask(with: request)
                } else {
                    self.session = URLSession(configuration: .default, delegate: self, delegateQueue: nil)
                    task = session!.dataTask(with: request)
                }
            } else {
                task = nil
            }
        }
    }

    deinit {
        eventsContinuation.finish()
    }

    // MARK: - Methods

    public func start() {
        guard let task = task else {
            return
        }

        switch state {
        case .completed, .started:
            return
        default:
            if session != nil {
                state = .started
                task.resume()
            } else if let validUrl = url {
                self.session = URLSession(configuration: .default, delegate: self, delegateQueue: nil)
                self.task = session!.dataTask(with: validUrl)
                state = .started
                self.task!.resume()
            }
        }
    }

    public func resume(_ resumableData: ResumableData) {
        guard let url = url else { return }
        stop()
        let bytesHave = resumableData.offset + resumableData.readyData
        var request = URLRequest(url: url)
        var headers = request.allHTTPHeaderFields ?? [:]
        headers["Range"] = "bytes=\(bytesHave)-"
        request.allHTTPHeaderFields = headers
        self.session = URLSession(configuration: .default, delegate: self, delegateQueue: nil)
        task = session!.dataTask(with: request)
        start()
    }

    public func pause() {
        guard let task = task else {
            return
        }

        guard state == .started else {
            return
        }

        state = .paused
        task.suspend()
    }

    public func stop() {
        totalBytesReceived = 0
        state = .stopped
        guard let task = task else {
            return
        }

        task.cancel()
    }
}
