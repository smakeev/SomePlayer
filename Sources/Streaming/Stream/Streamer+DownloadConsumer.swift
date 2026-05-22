//
//  Streamer+DownloadConsumer.swift
//  SomePlayer
//
//  Translates `DownloadEvent` values yielded by the downloader's AsyncStream
//  into parser/reader feeding and downstream delegate notifications. Invoked
//  from a Task on the audio pipeline's executor (see `setupAudioEngine`).
//

import Foundation
import AVFoundation

extension Streamer {

    /// Dispatches a single download event. Runs on the audio pipeline's
    /// executor; no thread-hopping inside.
    internal func handleDownloadEvent(_ event: DownloadEvent) {
        switch event {
        case .stateChanged(let newState):
            downloadingState = newState

        case .rangeHeader(let hasRange, let totalSize):
            delegate?.streamer(self, hasRangeHeader: hasRange, totalSize: totalSize)

        case .data(let data, let progress):
            handleDownloadData(data, progress: progress)

        case .completed(let error, let bytesReceived, let response):
            if let error = error, let url = downloader.url, let response = response {
                delegate?.streamer(self, failedDownloadWithError: error, forURL: url, readyData: bytesReceived, response: response)
            }
        }
    }

    private func handleDownloadData(_ data: Data, progress: Float) {
        if progressive && progressiveSeek != 0 && waitForProgress <= progress {
            waitForProgress = 0
        }
        guard let parser = parser else { return }

        do {
            try parser.parse(data: data)
        } catch {
            // Parse errors propagate via the parser's own diagnostics; the
            // consumer loop continues so subsequent chunks still flow.
        }

        // Lazily create the reader once the parser has discovered the data format.
        if reader == nil, parser.dataFormat != nil {
            do {
                self.reader = try Reader(parser: parser, readFormat: self.readFormat)
            } catch {
                // Same rationale as parse: do not break the consumer loop.
            }
        }

        notifyDownloadProgress(progress, bytes: Int64(data.count))
        handleDurationUpdate()
    }
}
