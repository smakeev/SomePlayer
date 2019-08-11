//
//  Streamer+DownloadingDelegate.swift
//  AudioStreamer
//
//  Created by Syed Haris Ali on 6/5/18.
//

import Foundation
import os.log

extension Streamer: DownloadingDelegate {
	
	public func download(_ download: Downloading, hasRangeHeader: Bool, totalSize: Int64) {
		//DispatchQueue.main.async { [unowned self] in
			self.delegate?.streamer(self, hasRangeHeader: hasRangeHeader, totalSize: totalSize)
		//}
	}
	
	public func download(_ download: Downloading, completedWithError error: Error?, bytesReceived: Int64, dataTask task: URLSessionTask) {
		//os_log("%@ - %d [error: %@]", log: Streamer.logger, type: .debug, #function, #line, String(describing: error?.localizedDescription))
		
		if let error = error, let url = download.url, let response = task.response {
		//	DispatchQueue.main.async { [unowned self] in
				self.delegate?.streamer(self, failedDownloadWithError: error, forURL: url, readyData: bytesReceived, response: response)
			}
		//}
	}
	
	public func download(_ download: Downloading, changedState downloadState: DownloadingState) {
//		//os_log("%@ - %d [state: %@]", log: Streamer.logger, type: .debug, #function, #line, String(describing: downloadState))
		//DispatchQueue.main.async { [unowned self] in
			self.downloadingState = downloadState
		//}
	}
	
	public func download(_ download: Downloading, didReceiveData data: Data, progress: Float) {
//		//os_log("%@ - %d", log: Streamer.logger, type: .debug, #function, #line)
		if progressive && progressiveSeek != 0 && waitForProgress <= progress {
			waitForProgress = 0
		}
		guard let parser = parser else {
			//os_log("Expected parser, bail...", log: Streamer.logger, type: .error)
			return
		}
		
//		DispatchQueue.main.async {
			//[weak self] in
			//guard let validSelf = self else { return }
			let validSelf = self
			/// Parse the incoming audio into packets
			do {
				try validSelf.parser?.parse(data: data)
			} catch {
				//os_log("Failed to parse: %@", log: Streamer.logger, type: .error, error.localizedDescription)
			}
			
			/// Once there's enough data to start producing packets we can use the data format
			if validSelf.reader == nil, let _ = validSelf.parser?.dataFormat {
				//print("!!! CREATE READER")
				do {
					validSelf.reader = try Reader(parser: parser, readFormat: validSelf.readFormat)
				} catch {
					//os_log("Failed to create reader: %@", log: Streamer.logger, type: .error, error.localizedDescription)
				}
			}
			
			/// Update the progress UI
			
			
			
			// Notify the delegate of the new progress value of the download
			validSelf.notifyDownloadProgress(progress, bytes: Int64(data.count))
			
			// Check if we have the duration
			validSelf.handleDurationUpdate()
//		}
	}
	
}
