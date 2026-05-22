//
//  Downloader+URLSessionDelegate.swift
//  AudioStreamer
//
//  Created by Syed Haris Ali on 1/6/18.
//
//  Phase 2 refactor: URLSession callbacks no longer hop to the main thread.
//  Each callback yields a `DownloadEvent` into the downloader's AsyncStream
//  and (for test back-compat) fires the existing handler closures. The
//  consumer (see Streamer+DownloadConsumer.swift) iterates the stream on
//  the audio pipeline's executor.
//

import Foundation
import os.log

extension Downloader: URLSessionDataDelegate {

    public func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse, completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
        totalBytesCount = response.expectedContentLength

        let hasRange: Bool
        if let httpResponse = response as? HTTPURLResponse {
            hasRange = (httpResponse.allHeaderFields["Accept-Ranges"] as? String) != nil
        } else {
            hasRange = false
        }
        eventsContinuation.yield(.rangeHeader(hasRange: hasRange, totalSize: totalBytesCount))
        completionHandler(.allow)
    }

    public func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        totalBytesReceived += Int64(data.count)
        progress = totalBytesCount > 0 ? Float(totalBytesReceived) / Float(totalBytesCount) : 0
        eventsContinuation.yield(.data(data, progress: progress))
        progressHandler?(data, progress)
    }

    public func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        // Ignore stale completions for tasks we've already replaced.
        guard self.task === task else { return }

        var errorToReturn: Error? = error
        if let validError = error as NSError? {
            if validError.code == -999 /* NSURLErrorCancelled */ {
                errorToReturn = nil
                state = .completed
            } else {
                state = .completedWithError
            }
        } else {
            state = .completed
        }

        eventsContinuation.yield(.completed(error: errorToReturn,
                                             bytesReceived: totalBytesReceived,
                                             response: task.response))
        completionHandler?(errorToReturn)

        session.invalidateAndCancel()
        if self.session === session {
            self.session = nil
        }
    }
}
