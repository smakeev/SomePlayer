//
//  StreamingDelegate.swift
//  AudioStreamer
//
//  Created by Syed Haris Ali on 6/5/18.
//

import Foundation
import AVFoundation

/// The `StreamingDelegate` provides an interface for responding to changes to a `Streaming` instance. These include whenever the streamer state changes, when the download progress changes, as well as the current time and duration changes.
public protocol StreamingDelegate: class {

	func streamer(_ streamer: Streaming, fileFinished url: URL)

	func streamer(_ streamer: Streaming, hasRangeHeader: Bool, totalSize: Int64)
	
	/// Triggered when the downloader fails
	///
	/// - Parameters:
	///   - streamer: The current `Streaming` instance
	///   - error: An `Error` representing the reason the download failed
	///   - url: A `URL` representing the current resource the progress value is for.
	func streamer(_ streamer: Streaming, failedDownloadWithError error: Error, forURL url: URL, readyData bytes: Int64, response: URLResponse)
	
	/// Triggered when the downloader's progress value changes.
	///
	/// - Parameters:
	///   - streamer: The current `Streaming` instance
	///   - progress: A `Float` representing the current progress ranging from 0 - 1.
	///   - url: A `URL` representing the current resource the progress value is for.
    func streamer(_ streamer: Streaming, updatedDownloadProgress progress: Float, bytesReceived bytes: Int64, forURL url: URL)
	
	/// Triggered when the playback `state` changes.
	///
	/// - Parameters:
	///   - streamer: The current `Streaming` instance
	///   - state: A `StreamingState` representing the new state value.
	func streamer(_ streamer: Streaming, changedState state: StreamingState)
	
	/// Triggered when the current play time is updated.
	///
	/// - Parameters:
	///   - streamer: The current `Streaming` instance
	///   - currentTime: A `TimeInterval` representing the new current time value.
	func streamer(_ streamer: Streaming, updatedCurrentTime currentTime: TimeInterval)
	
	/// Triggered when the duration is updated.
	///
	/// - Parameters:
	///   - streamer: The current `Streaming` instance
	///   - duration: A `TimeInterval` representing the new duration value.
	func streamer(_ streamer: Streaming, updatedDuration duration: TimeInterval)
	
	func streamer(_ streamer: Streaming, willProvideFormat format: AVAudioFormat?)
	
	func streamer(_ streamer: Streaming, isBuffering: Bool)

	//This only works in case of proressive downloading
	func streamer(_ streamer: Streaming, isWaitingDownloader waiting: Bool)

	//errors
	func streamerFailedToStartEngine(_ streamer: Streaming)
	func streamerFailedToScheduleBuffer(_ streamer: Streaming)
	func streamerFailedToCreateParser(_ streamer: Streaming)
}
