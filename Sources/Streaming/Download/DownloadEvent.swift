//
//  DownloadEvent.swift
//  SomePlayer
//
//  Events emitted by `Downloader` via `events: AsyncStream<DownloadEvent>`.
//  Consumers iterate the stream from a Task isolated to whichever executor
//  they want the work to land on.
//

import Foundation

public enum DownloadEvent: Sendable {
    /// The downloader transitioned to a new state.
    case stateChanged(DownloadingState)

    /// The HTTP response was received; reports whether the server supports
    /// range requests and the total content length (-1 if unknown).
    case rangeHeader(hasRange: Bool, totalSize: Int64)

    /// A chunk of data arrived. `progress` is the fraction of total bytes
    /// received for this task (0–1), or NaN if the total is unknown.
    case data(Data, progress: Float)

    /// The data task finished. `error` is nil on success or when cancelled
    /// (NSURLErrorCancelled is filtered to nil to match prior behaviour).
    case completed(error: (any Error)?, bytesReceived: Int64, response: URLResponse?)
}
