//
//  Streamer.swift
//  AudioStreamer
//
//  Created by Syed Haris Ali on 6/5/18.
//  Copyright © 2018 Ausome Apps LLC. All rights reserved.
//

import AVFoundation
import Foundation
import os.log

/// The `Streamer` is a concrete implementation of the `Streaming` protocol and is intended to provide a high-level, extendable class for streaming an audio file living at a URL on the internet. Subclasses can override the `attachNodes` and `connectNodes` methods to insert custom effects.
open class Streamer: Streaming {
	static let logger = OSLog(subsystem: "com.fastlearner.streamer", category: "Streamer")
	
	// MARK: - Properties (Streaming)
	
	public var currentTime: TimeInterval? {
		guard let nodeTime = playerEngineNode.lastRenderTime,
			let playerTime = playerEngineNode.playerTime(forNodeTime: nodeTime) else {
				return currentTimeOffset
		}
		let currentTime = TimeInterval(playerTime.sampleTime) / playerTime.sampleRate
		return currentTime + currentTimeOffset
	}
	weak public var delegate: StreamingDelegate?
	public internal(set) var duration:        TimeInterval?
	public internal(set) var totalDuration:   TimeInterval = 0
	public internal(set) var totalTimeOffset: TimeInterval = 0
	
	public lazy var downloader: Downloading = {
		let downloader = Downloader()
		downloader.delegate = self
		return downloader
	}()
	public internal(set) var parser: Parsing?
	public internal(set) var reader: Reading?
	public let engine = AVAudioEngine()
	public let playerEngineNode = AVAudioPlayerNode()
	public internal(set) var state: StreamingState = .stopped {
		didSet {
			delegate?.streamer(self, changedState: state)
		}
	}

	public var isLocal: Bool = false

	public var url: URL? {
		didSet {
			reset()
			if !isLocal {
				if let url = url {
					downloader.url = url
					downloader.start()
				}
			} else {
				if let url = url {
					audioFile = try? AVAudioFile(forReading: url)
				}
			}
		}
	}

	public var volume: Float {
		get {
			return engine.mainMixerNode.outputVolume
		}
		set {
			engine.mainMixerNode.outputVolume = newValue
		}
	}
	var scheduleNextBufferTimer: Timer?
	var volumeRampTimer: Timer?
	var volumeRampTargetValue: Float?
	
	// MARK: - Properties
	
	/// A `TimeInterval` used to calculate the current play time relative to a seek operation.
	var currentTimeOffset: TimeInterval = 0
	
	/// A `Bool` indicating whether the file has been completely scheduled into the playerEngine node.
	var isFileSchedulingComplete = false
	
	// MARK: - Lifecycle
	
	public init() {        
		// Setup the audio engine (attach nodes, connect stuff, etc). No playback yet.
		setupAudioEngine()
	}
	
	// MARK: - Setup
	
	func setupAudioEngine() {
		os_log("%@ - %d", log: Streamer.logger, type: .debug, #function, #line)
		
		// Attach nodes
		attachNodes()
		
		// Node nodes
		connectNodes()
		
		// Prepare the engine
		engine.prepare()
		
		/// Use timer to schedule the buffers (this is not ideal, wish AVAudioEngine provided a pull-model for scheduling buffers)
		let interval = (1 / (readFormat.sampleRate / Double(readBufferSize))) / 100
		scheduleNextBufferTimer = Timer(timeInterval: interval / 2, repeats: true) {
			[weak self] _ in
			guard self != nil else {
				return
			}
			guard self?.state != .stopped else {
				return
			}
			//guard self?.isLocal != true else { return }

			if self?.isLocal != true {
				self?.scheduleNextBuffer()
			}
			self?.handleTimeUpdate()
			self?.notifyTimeUpdated()
		}
		if let timer = scheduleNextBufferTimer {
			RunLoop.current.add(timer, forMode: .common)
		}
	}
	
	/// Subclass can override this to attach additional nodes to the engine before it is prepared. Default implementation attaches the `playerEngineNode`. Subclass should call super or be sure to attach the playerEngineNode.
	open func attachNodes() {
		engine.attach(playerEngineNode)
	}
	
	/// Subclass can override this to make custom node connections in the engine before it is prepared. Default implementation connects the playerEngineNode to the mainMixerNode on the `AVAudioEngine` using the default `readFormat`. Subclass should use the `readFormat` property when connecting nodes.
	open func connectNodes() {
		engine.connect(playerEngineNode, to: engine.mainMixerNode, format: readFormat)
	}
	
	// MARK: - Reset

	deinit{
		scheduleNextBufferTimer?.invalidate()
	}

	func reset() {
		os_log("%@ - %d", log: Streamer.logger, type: .debug, #function, #line)
		
		// Reset the playback state
		stop()
		currentTimeOffset = 0
		duration = nil
		reader = nil
		isFileSchedulingComplete = false
		
		// Create a new parser
		do {
			parser = try Parser()
			parser?.formatObserver = { [weak self] format in
				guard let validSelf = self else { return }
				self?.delegate?.streamer(validSelf, willProvideFormat: format)
			}
		} catch {
			os_log("Failed to create parser: %@", log: Streamer.logger, type: .error, error.localizedDescription)
		}
	}
	
	// MARK: - Methods
	
	public func resume(_ resumableData: ResumableData) {
		downloader.resume(resumableData)
	}
	
	public func play() {
		os_log("%@ - %d", log: Streamer.logger, type: .debug, #function, #line)
		
		// Check we're not already playing
		guard !playerEngineNode.isPlaying else {
			return
		}
		
		if !engine.isRunning {
			do {
				try engine.start()
			} catch {
				os_log("Failed to start engine: %@", log: Streamer.logger, type: .error, error.localizedDescription)
			}
		}
		
		// To make the volume change less harsh we mute the output volume
		let lastVolume = volumeRampTargetValue ?? volume
		volume = 0
		
		// Start playback on the playerEngine node
		playerEngineNode.play()
		
		// After 250ms we restore the volume to where it was
		swellVolume(to: lastVolume)
		
		// Update the state
		state = .playing
	}
	
	public func pause() {
		os_log("%@ - %d", log: Streamer.logger, type: .debug, #function, #line)
		
		// Check if the playerEngine node is playing
		guard playerEngineNode.isPlaying else {
			return
		}
		
		// Pause the playerEngine node and the engine
		playerEngineNode.pause()
		
		// Update the state
		state = .paused
	}
	
	public func stop() {
		os_log("%@ - %d", log: Streamer.logger, type: .debug, #function, #line)
		
		// Stop the downloader, the playerEngine node, and the engine
		downloader.stop()
		playerEngineNode.stop()
		engine.stop()
		
		// Update the state
		state = .stopped
	}

	var seekFrame: AVAudioFramePosition = 0
	var currentPosition: AVAudioFramePosition = 0
	private func seekLocal(to time: TimeInterval) {
		guard let audioFile = audioFile else { return }
		let isPlaying = playerEngineNode.isPlaying
		let lastVolume = volumeRampTargetValue ?? volume
		seekFrame = AVAudioFramePosition(Float(time) * audioSampleRate)
		seekFrame = max(seekFrame, 0)
		seekFrame = min(seekFrame, audioLengthSamples)
		currentPosition = seekFrame
		playerEngineNode.stop()
		volume = 0

		if currentPosition < audioLengthSamples {
			currentTimeOffset = time
			isFileSchedulingComplete = false

			playerEngineNode.scheduleSegment(audioFile, startingFrame: seekFrame, frameCount: AVAudioFrameCount(audioLengthSamples - seekFrame), at: nil) { [weak self] in
					self?.isFileSchedulingComplete = true
			}
		}

		if isPlaying {
			playerEngineNode.play()
		}

		// Update the current time
		delegate?.streamer(self, updatedCurrentTime: time)

		// After 250ms we restore the volume back to where it was
		swellVolume(to: lastVolume)
	}
	
	public func seek(to time: TimeInterval, internalUse: Bool = false) throws {
		os_log("%@ - %d [%.1f]", log: Streamer.logger, type: .debug, #function, #line, time)
		
		if isLocal {
			seekLocal(to: time)
			return
		}

		// Make sure we have a valid parser and reader
		guard let parser = parser, let reader = reader else {
			return
		}
		
		// Get the proper time and packet offset for the seek operation
		guard let frameOffset = parser.frameOffset(forTime: time),
			let packetOffset = parser.packetOffset(forFrame: frameOffset) else {
				return
		}
		currentTimeOffset = time
		isFileSchedulingComplete = false
		
		// We need to store whether or not the playerEngine node is currently playing to properly resume playback after
		let isPlaying = playerEngineNode.isPlaying
		let lastVolume = volumeRampTargetValue ?? volume
		
		// Stop the playerEngine node to reset the time offset to 0
		playerEngineNode.stop()
		volume = 0
		
		// Perform the seek to the proper packet offset
		do {
			try reader.seek(packetOffset)
		} catch {
			os_log("Failed to seek: %@", log: Streamer.logger, type: .error, error.localizedDescription)
			return
		}
		
		// If the playerEngine node was previous playing then resume playback
		if isPlaying {
			playerEngineNode.play()
		}
		
		// Update the current time
		delegate?.streamer(self, updatedCurrentTime: time)
		
		if internalUse {
			engine.mainMixerNode.outputVolume = lastVolume
		} else {
			// After 250ms we restore the volume back to where it was
			swellVolume(to: lastVolume)
		}
	}
	
	func swellVolume(to newVolume: Float, duration: TimeInterval = 0.5) {
		volumeRampTargetValue = newVolume
		DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(Int(duration*1000/2))) { [weak self] in
			guard let validSelf = self else { return }
			validSelf.volumeRampTimer?.invalidate()
			let timer = Timer(timeInterval: Double(Float((duration/2.0))/(newVolume * 10)), repeats: true) { [weak self] timer in
				guard let validSelf = self else { return }
				if validSelf.volume != newVolume {
					validSelf.volume = min(newVolume, validSelf.volume + 0.1)
				} else {
					validSelf.volumeRampTimer = nil
					validSelf.volumeRampTargetValue = nil
					timer.invalidate()
				}
			}
			RunLoop.current.add(timer, forMode: .common)
			validSelf.volumeRampTimer = timer
		}
	}
	
	// MARK: - Scheduling Buffers
	//schedulefile for local file
	
	func openLocal(_ url: URL) {
		isLocal = true
		self.url = url
	}

	func openRemote(_ url: URL) {
		isLocal = false
		self.url = url
	}

	var format: AVAudioFormat?
	var audioSampleRate: Float = 0
	var audioLengthSeconds: Float = 0
	var audioLengthSamples: AVAudioFramePosition = 0
	var audioFile: AVAudioFile? {
		didSet {
			if let audioFile = audioFile {
				audioLengthSamples = audioFile.length
				format = audioFile.processingFormat
				audioSampleRate = Float(format?.sampleRate ?? 44100)
				audioLengthSeconds = Float(audioLengthSamples) / audioSampleRate
				scheduleFile()
				self.duration = TimeInterval(audioLengthSeconds)
				notifyDurationUpdate(self.duration!)
				notifyDownloadProgress(1.0, bytes: audioFile.length)
			}
		}
	}

	func scheduleFile() {
		guard !isFileSchedulingComplete else {
			return
		}
		guard let validAudioFile = audioFile else {
			return
		}

		playerEngineNode.scheduleFile(validAudioFile, at: nil) {  [weak self] in
			self?.isFileSchedulingComplete = true
		}
	}

	private let packetsMaxToSchedule: Int = 100
	private var lastSteppedPacket:    Int = 0
	func scheduleNextBuffer() {
		guard let reader = reader else {
			os_log("No reader yet...", log: Streamer.logger, type: .debug)
			return
		}
		
		guard !isFileSchedulingComplete else {
			return
		}

		if lastSteppedPacket > packetsMaxToSchedule {
			return
		}
		do {
			let nextScheduledBuffer = try reader.read(readBufferSize)
			lastSteppedPacket += 1
			playerEngineNode.scheduleBuffer(nextScheduledBuffer) { [weak self] in
				guard let validSelf = self else { return }
				DispatchQueue.main.async {
					validSelf.lastSteppedPacket -= 1
					print("@@@ \(validSelf.lastSteppedPacket)")
				}
			}
		} catch ReaderError.reachedEndOfFile {
			os_log("Scheduler reached end of file", log: Streamer.logger, type: .debug)
			isFileSchedulingComplete = true
		} catch ReaderError.notEnoughData {
			os_log("Scheduler reached end of parsed part", log: Streamer.logger, type: .debug)
		} catch {
			os_log("Cannot schedule buffer: %@", log: Streamer.logger, type: .debug, error.localizedDescription)
		}
	}
	
	// MARK: - Handling Time Updates
	
	/// Handles the duration value, explicitly checking if the duration is greater than the current value. For indeterminate streams we can accurately estimate the duration using the number of packets parsed and multiplying that by the number of frames per packet.
	func handleDurationUpdate() {
		if let newDuration = parser?.duration {
			// Check if the duration is either nil or if it is greater than the previous duration
			var shouldUpdate = false
			if duration == nil {
				shouldUpdate = true
			} else if let oldDuration = duration, oldDuration < newDuration {
				shouldUpdate = true
			}
			
			// Update the duration value
			if shouldUpdate {
				self.duration = newDuration
				notifyDurationUpdate(newDuration)
			}
		}
	}
	
	/// Handles the current time relative to the duration to make sure current time does not exceed the duration
	func handleTimeUpdate() {
		guard let currentTime = currentTime else {
			return
		}
		guard let duration = self.duration else { return }

		if currentTime + totalTimeOffset >= max(duration, totalDuration) {
			try? seek(to: 0)
			pause()
			//inform that file finished
			if let url = self.url {
				self.delegate?.streamer(self, fileFinished: url)
			}
		}
	}
	
	// MARK: - Notifying The Delegate
	
	func notifyDownloadProgress(_ progress: Float, bytes: Int64) {
		guard let url = url else {
			return
		}
		
		delegate?.streamer(self, updatedDownloadProgress: progress, bytesReceived: bytes, forURL: url)
	}
	
	func notifyDurationUpdate(_ duration: TimeInterval) {
		guard let _ = url else {
			return
		}
		
		delegate?.streamer(self, updatedDuration: duration)
	}
	
	func notifyTimeUpdated() {
		guard engine.isRunning, playerEngineNode.isPlaying else {
			return
		}
		
		guard let currentTime = currentTime else {
			return
		}

		delegate?.streamer(self, updatedCurrentTime: currentTime)
	}
}
