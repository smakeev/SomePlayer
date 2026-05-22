//
//  Streamer+DownloadConsumer.swift
//  SomePlayer
//
//  Consumer-side translation of `DownloadEvent` into the streamer's existing
//  pipeline (parser feed, reader creation, downstream delegate notifications).
//  Invoked from a Task on the audio pipeline's executor — see
//  `setupAudioEngine` in Streamer.swift.
//
//  Replaces the prior `Streamer: DownloadingDelegate` conformance, which
//  forced every callback through the main thread.
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
            // Logged at the parser layer; ignore here to preserve stream consumption.
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
