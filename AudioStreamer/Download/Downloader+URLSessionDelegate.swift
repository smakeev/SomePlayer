//
//  Downloader+URLSessionDelegate.swift
//  AudioStreamer
//
//  Created by Syed Haris Ali on 1/6/18.
//

import Foundation
import os.log

extension Downloader: URLSessionDataDelegate {
	public func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse, completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
		os_log("%@ - %d", log: Downloader.logger, type: .debug, #function, #line)
		DispatchQueue.main.async {
			self.totalBytesCount = response.expectedContentLength
			
			if let httpResponse = response as? HTTPURLResponse {
				if let _ = httpResponse.allHeaderFields["Accept-Ranges"] as? String {
					self.delegate?.download(self, hasRangeHeader: true, totalSize: self.totalBytesCount)
				} else {
					self.delegate?.download(self, hasRangeHeader: false, totalSize: self.totalBytesCount)
				}
			}
			completionHandler(.allow)
		}
	}
	
	public func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
		os_log("%@ - %d", log: Downloader.logger, type: .debug, #function, #line, data.count)
		DispatchQueue.main.async {
			self.totalBytesReceived += Int64(data.count)
			self.progress = Float(self.totalBytesReceived) / Float(self.totalBytesCount)
			
			self.delegate?.download(self, didReceiveData: data, progress: self.progress)
			self.progressHandler?(data, self.progress)
		}
	}
	
	public func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
		os_log("%@ - %d", log: Downloader.logger, type: .debug, #function, #line)
		DispatchQueue.main.async {
			if self.task === task {
				self.state = .completed
			} else {
				return
			}
			var errorToReturn: Error? = error
			
			if let validError = error as NSError? {
				if validError.code == -999 {
					errorToReturn = nil
				} else {
					self.state = .completedWithError
				}
			}
			
			self.delegate?.download(self, completedWithError: errorToReturn, bytesReceived: self.self.totalBytesReceived, dataTask: task)
			self.completionHandler?(errorToReturn)
			
			session.invalidateAndCancel()
			
			if self.session === session {
				self.session = nil
			}
		}
	}
}
