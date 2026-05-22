//
//  Downloading.swift
//  AudioStreamer
//
//  Created by Syed Haris Ali on 1/6/18.
//

import Foundation

/// The `Downloading` protocol represents a generic downloader that can be used for grabbing a fixed length audio file.
public protocol Downloading: AnyObject, Sendable {

    // MARK: - Properties

    /// Async stream of download events. Single-iteration — only one consumer
    /// per `Downloading` instance. See `DownloadEvent` for the payloads.
    var events: AsyncStream<DownloadEvent> { get }

    /// A completion block for when the contents of the download are fully downloaded.
    var completionHandler: ((Error?) -> Void)? { get set }

    /// The current progress of the downloader. Ranges from 0.0 - 1.0, default is 0.0.
    var progress: Float { get }

    /// The current state of the downloader. See `DownloadingState` for the different possible states.
    var state: DownloadingState { get }

    /// A `URL` representing the current URL the downloader is fetching. This is an optional because this protocol is designed to allow classes implementing the `Downloading` protocol to be used as singletons for many different URLS so a common cache can be used to redownloading the same resources.
    var url: URL? { get set }

    /// If non-zero, the downloader sleeps for this many milliseconds
    /// between each `URLSession` data chunk before yielding it to the event
    /// stream. Default is 0 (no throttling).
    var simulatedChunkDelayMilliseconds: UInt { get set }

    // MARK: - Methods

    /// Starts the downloader
    func start()

    /// Pauses the downloader
    func pause()

    /// Stops and/or aborts the downloader. This should invalidate all cached data under the hood.
    func stop()

    func resume(_ resumableData: ResumableData)

}
