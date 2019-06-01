//
//  Player.swift
//  AudioStreamer
//
//  Created by Sergey Makeev on 29/05/2019.
//  Copyright © 2019 Ausome Apps LLC. All rights reserved.
//

import Foundation

public protocol SomePlayerDelegate: class {
	func player(_ player: SomePlayer, failedDownloadWithError error: Error, forURL url: URL)
	func player(_ player: SomePlayer, updatedDownloadProgress progress: Float, forURL url: URL)
	func player(_ player: SomePlayer, changedState state: StreamingState)
	func player(_ player: SomePlayer, updatedCurrentTime currentTime: TimeInterval)
	func player(_ player: SomePlayer, updatedDuration duration: TimeInterval)
	func player(_ player: SomePlayer, savedSeconds: TimeInterval)
}


open class SomePlayer: NSObject {
	
	public enum SilenceHandlingType {
		case none
		case smart
		case speedUp
	}
	
	public var silenceHandlingType: SilenceHandlingType = .none {
		didSet {
			amplitudes = [Float]()
			self.rate = self.baseRate
		}
	}
	
	public internal(set) var fileDownloaded: Bool  = false {
		didSet {
			if fileDownloaded == true {
				resumableData = nil
			}
		}
	}
	public internal(set) var rangeHeader:    Bool  = false
	public internal(set) var totalSize:      Int64 = 0
	//public internal(set) var hasBytes:       Int64 = 0
	public               var offset:         Int64 = 0 {
		didSet {
			resumableData = nil
		}
	}
	public internal(set) var hasError:       Bool = false
	
	public fileprivate(set) var resumableData: ResumableData?
	
	
	public func resume() {
		guard !fileDownloaded else { return }
		if resumableData == nil {
			//just start from the beginnig
			streamer.url = self.url
		} else {
			streamer.resume(resumableData!)
		}
	}
	
	public var sampleRate: Double? {
		get {
			return streamer.parser?.dataFormat?.sampleRate
		}
	}
	
	weak public var delegate: SomePlayerDelegate? = nil
	
	lazy public internal(set) var streamer: TimePitchStreamer = {
		let streamer = TimePitchStreamer()
		streamer.delegate = self
		return streamer
	}()
	
	public var url: URL? {
		get { return streamer.url }
		set {
			streamer.url = newValue
		}
	}
	
	public var state: StreamingState {
		get {
			return streamer.state
		}
	}
	
	public func pause() {
		streamer.pause()
	}
	
	public func play() {
		if hasError {
			resume()
		}
		streamer.play()
	}
	
	public func seek(to time: TimeInterval) {
		do{
			amplitudes = [Float]()
			self.rate = self.baseRate
			try streamer.seek(to: time)
		}
		catch {
			///
		}
	}
	
	public var pitch: Float {
		get {
			return streamer.pitch
		}
		set {
			streamer.pitch = newValue
		}
	}
	
	public var baseRate: Float = 1.0 {
		didSet {
			self.rate = baseRate
		}
	}
	
	public internal(set) var rate: Float {
		get {
			return streamer.rate
		}
		set {
			streamer.rate = newValue
			for observer in rateObservers.values {
				observer(newValue)
			}
		}
	}
	
	fileprivate var rateObservers: [String : (Float)->Void] = [String : (Float)->Void]()
	public func addRateObserver(withId id: String, observer: @escaping (Float)->Void) {
		rateObservers[id] = observer
	}
	
	public func removeRateObserver(withId id: String) {
		rateObservers[id] = nil
	}
	
	private var amplitudes: [Float] = [Float]()
	
	private func handleSilence() {
		
		func informForsavedTime() {
			if let validSampleRate = self.sampleRate {
			 	let interval:Double = Double(1 / (validSampleRate / Double(streamer.readBufferSize)))
				let savedSeconds: Double = Double(interval - (interval / Double(self.rate)))
				self.delegate?.player(self, savedSeconds: savedSeconds)
			}
		}
		
		if silenceHandlingType == .none {
			return
		}
		
		if silenceHandlingType == .speedUp {
			let decibelThreshold = Float(-35)
			
			if let average = averagePowerForChannel0 {
				if average < decibelThreshold {
					self.rate = 3
					informForsavedTime()
				} else {
					self.rate = Float(baseRate)
				}
			}
			return
		}
		
		if silenceHandlingType == .smart {
			guard let average = self.averagePowerForChannel0 else { return }
			amplitudes.append(average + 120)
			guard amplitudes.count > 10 else { return }
			if self.amplitudes.last! > 50 {
				self.rate = baseRate + (amplitudes.max()! - amplitudes.last!) * 0.01
			} else {
				self.rate = baseRate + (amplitudes.max()! - amplitudes.last!) * 0.02
			}
			informForsavedTime()
			return
		}
	}
	
	public fileprivate(set) var averagePowerForChannel0: Float? = nil {
		didSet {
			handleSilence()
		}
	}
	public fileprivate(set) var averagePowerForChannel1: Float? = nil {
		didSet {
			//print("CH1 \(String(describing: averagePowerForChannel1))")
		}
	}
	
}

extension SomePlayer: StreamingDelegate {
	
	private func setAveragePowerCh1(_ power: Float?) {
		DispatchQueue.main.async {
			self.averagePowerForChannel1 = power
		}
	}
	
	private func averagePowerForChannel0Toch1() {
		DispatchQueue.main.async {
			self.averagePowerForChannel1 = self.averagePowerForChannel0
		}
	}
	
	private func setAveragePowerCh0(_ power: Float?) {
		DispatchQueue.main.async {
			self.averagePowerForChannel0 = power
		}
	}
	
	public func streamer(_ streamer: Streaming, hasRangeHeader: Bool, totalSize: Int64) {
		self.totalSize = totalSize
		self.rangeHeader = hasRangeHeader
	}
	
	public func streamer(_ streamer: Streaming, failedDownloadWithError error: Error, forURL url: URL, readyData bytes: Int64, response: URLResponse) {
		hasError = true
		resumableData = ResumableData(offset: offset, response: response, readyData: bytes)
		delegate?.player(self, failedDownloadWithError: error, forURL: url)
	}
	
	public func streamer(_ streamer: Streaming, updatedDownloadProgress progress: Float, forURL url: URL) {
		delegate?.player(self, updatedDownloadProgress: progress, forURL: url)
		hasError = false
		if progress == 1.0 {
			fileDownloaded = true
		}
	}
	
	public func streamer(_ streamer: Streaming, changedState state: StreamingState) {
		amplitudes = [Float]()
		self.rate = self.baseRate
		delegate?.player(self, changedState: state)
		let mainMixer = streamer.engine.mainMixerNode
		if state == .playing {
			let bufferSize = streamer.readBufferSize
			let format = mainMixer.outputFormat(forBus: 0)
			print(format)
			mainMixer.installTap(onBus: 0, bufferSize: bufferSize, format: format) { buffer, when in
				buffer.frameLength = bufferSize
				
				if buffer.format.channelCount > 0 {
					let channelData = buffer.floatChannelData
					if let validChannelData = channelData {
						let channelDataValue = validChannelData[0]
						let channelDataValueArray = stride(from: 0,
														   to: Int(buffer.frameLength),
														   by: buffer.stride).map{ channelDataValue[$0] }
						let rms = sqrt(channelDataValueArray.map{ $0 * $0 }.reduce(0, +) / Float(buffer.frameLength))
						self.setAveragePowerCh0(20 * log10(rms))
						
					} else {
						self.setAveragePowerCh0(nil)
						self.setAveragePowerCh1(nil)
						return
					}
				} else {
					self.setAveragePowerCh0(nil)
					self.setAveragePowerCh1(nil)
					return
				}
				
				if buffer.format.channelCount > 1 {
					let channelData = buffer.floatChannelData
					if let validChannelData = channelData {
						let channelDataValue = validChannelData[1]
						let channelDataValueArray = stride(from: 0,
														   to: Int(buffer.frameLength),
														   by: buffer.stride).map{ channelDataValue[$0] }
						let rms = sqrt(channelDataValueArray.map{ $0 * $0 }.reduce(0, +) / Float(buffer.frameLength))
						self.setAveragePowerCh1(20 * log10(rms))
						
					} else {
						self.setAveragePowerCh1(nil)
					}
				} else {
					self.averagePowerForChannel0Toch1()
				}
			}
		} else {
			mainMixer.removeTap(onBus: 0)
		}
	}
	
	public func streamer(_ streamer: Streaming, updatedCurrentTime currentTime: TimeInterval) {
		delegate?.player(self, updatedCurrentTime: currentTime)
	}
	
	public func streamer(_ streamer: Streaming, updatedDuration duration: TimeInterval) {
		delegate?.player(self, updatedDuration: duration)
	}
}
