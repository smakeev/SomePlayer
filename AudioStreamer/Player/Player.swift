//
//  Player.swift
//  AudioStreamer
//
//  Created by Sergey Makeev on 29/05/2019.
//  Copyright © 2019 Ausome Apps LLC. All rights reserved.
//

import Foundation
import AVFoundation
import UIKit

public protocol SomePlayerDelegate: class {
	func player(_ player: SomePlayer, failedDownloadWithError error: Error, forURL url: URL)
	func player(_ player: SomePlayer, updatedDownloadProgress progress: Float, currentTaskProgress currentProgress: Float, forURL url: URL)
	func player(_ player: SomePlayer, changedState state: SomePlayer.PlayerState)
	func player(_ player: SomePlayer, updatedCurrentTime currentTime: TimeInterval)
	func player(_ player: SomePlayer, updatedDuration duration: TimeInterval)
	func player(_ player: SomePlayer, savedSeconds: TimeInterval)
	func player(_ player: SomePlayer, offsetChanged offset: Int64)
}


open class SomePlayer: NSObject {

	public enum PlayerState: Int {
		case undefined = 0
		case initializing
		case ready
		case playing
		case paused
		case ended
		case failed
	}

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
	
	public internal(set) var format: AVAudioFormat? {
		didSet {
			//calc est duration.
			guard totalSize > 0 else { return }
			guard let format = format else {
				estimatedDuration = 0
				return
			}

			let framesPerPacket = format.streamDescription.pointee.mFramesPerPacket
			let bytesPerPacket = format.streamDescription.pointee.mBytesPerPacket
			//let packets = totalSize / bytesPerPacket
			//let frames = Int64(framesPerPacket) * packets
			
			//estimatedDuration = TimeInterval(frames) / TimeInterval(format.sampleRate)
			//print(estimatedDuration.toMMSS())
		}
	}

	public fileprivate(set) var state: PlayerState = .undefined {
		didSet {
			if state != oldValue {
				self.delegate?.player(self, changedState: state)
			}
		}
	}

	public var duration:         TimeInterval {
		get {
			return max(hasDuration, estimatedDuration)
		}
	}

	public internal(set) var hasDuration:       TimeInterval = 0 {
		didSet {

		}
	}
	public internal(set) var estimatedDuration: TimeInterval = 0 {
		didSet {
			self.delegate?.player(self, updatedDuration: self.duration)
		}
	}
	
	
	public internal(set) var rangeHeader:    Bool  = false
	public internal(set) var totalSize:      Int64 = 0 {
		didSet {
			print("!!! TOtalSize: \(totalSize)")
		}
	}
	public internal(set) var hasBytes:       Int64 = 0 {
		didSet {

			if hasBytes > totalSize {
				totalSize = hasBytes
			}
		}
	}
	public               var offset:         Int64 = 0 {
		didSet {
			resumableData = nil
			hasBytes = 0
			delegate?.player(self, offsetChanged: offset)

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

    public var isLocal: Bool = false

	public internal(set) var url: URL? {
		get { return streamer.url }
		set {
			guard let validURL = newValue else { return }
			if !isLocal {
				streamer.openRemote(validURL)
			} else {
				streamer.openLocal(validURL)
			}
		}
	}

//    var audioLengthSeconds: Float = 0
//    var audioLengthSamples: AVAudioFramePosition = 0
//    var audioSampleRate: Float = 0


	public private(set) var title: String? {
		didSet {

		}
	}
	public private(set) var artist: String? {
		didSet {
			
		}
	}
	public private(set) var album: String? {
		didSet {

		}
	}
	public private(set) var image: UIImage? {
		didSet {

		}
	}


	private var asset: AVAsset?
	private var id3Parser: ID3Parser?
	private func handleMeta(_ url: URL, handler: @escaping ()-> Void) {
		self.state = .initializing
		DispatchQueue.global().async {
			if self.id3Parser != nil {
				self.id3Parser?.cancel()
			}
			self.id3Parser = ID3Parser(url)
			self.id3Parser?.parse()

			let asset = AVURLAsset(url: url)
			//let metadata = asset.commonMetadata
			let availableMetaFormats = asset.availableMetadataFormats
			for format in availableMetaFormats {
				for item in asset.metadata(forFormat: format) {
					if let commonKey = item.commonKey {

						if commonKey.rawValue == "title" {
							DispatchQueue.main.async {
								self.title = item.value as? String
							}
							continue
						}
						if commonKey.rawValue == "artist" {
							DispatchQueue.main.async {
								self.artist = item.value as? String
							}
							continue
						}
						if commonKey.rawValue == "albumName" {
							DispatchQueue.main.async {
								self.album = item.value as? String
							}
							continue
						}
						if commonKey.rawValue == "artwork" {
							if let value = item.value {
								if let data = value as? Data {
									DispatchQueue.main.async {
										self.image = UIImage(data: data)
									}
								}
							}
							continue
						}
					}
				}
			}
			DispatchQueue.main.async {
				self.estimatedDuration = TimeInterval(CMTimeGetSeconds(asset.duration))
//				for track in asset.tracks(withMediaType: AVMediaType.audio) {

//					let formatDescrptions = track.formatDescriptions
//					if formatDescrptions.count > 0 {
//						formatDescription = formatDescrptions[0]
//						print("!!! desc: \(formatDescription)
//					}
//					print("!!! track.estimatedDataRate \(track.estimatedDataRate)")
//					print("!!! track.totalSampleDataLength \(track.totalSampleDataLength)")
//					print("!!! track.naturalSize \(track.naturalSize)")
//					print("!!! track.minFrameDuration \(track.minFrameDuration)")

//					for segment in track.segments {
//						print("!!! \(segment.timeMapping)")
//					}
//				}
//				print("!!! \(self.estimatedDuration)")
//				if asset.providesPreciseDurationAndTiming {
//					self.asset = asset
//				} else {
//					self.asset = nil
//				}
				handler()
				self.state = .ready
			}
		}
	}
	public func openRemote(_ url: URL) {
		isLocal = false
		streamer.reset()
		fileDownloaded = false
		hasError = false
		rangeHeader = false
		handleMeta(url) {
			self.url = url
		}
	}

	public func openLocal(_  url: URL) {
		isLocal = true
		streamer.reset()
		fileDownloaded = true
		hasError = false
		rangeHeader = false
		handleMeta(url) {
			self.url = url
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

	public func seekPercently(to percent: Float) {
		guard percent >= 0.0 && percent <= 1.0 else { return }
		if fileDownloaded {
			let intervalToSeek = hasDuration * TimeInterval(percent)
			seek(to: intervalToSeek)
			return
		}

		//check if we in downloaded part
		let weAreHere = offset + hasBytes
		let percentWeAre = Float(weAreHere) / Float(totalSize)
		let percentOffset = Float(offset) / Float(totalSize)
		if percent >= percentOffset &&
		   percent <= percentWeAre {

			//We are inside downloaded area
			let percentWide = percentWeAre - percentOffset
			//let timeToSeek = (TimeInterval(percent) * hasDuration) / TimeInterval(percentWide)
			let hasWide = percent - percentOffset
			let realPercent = hasWide / percentWide
			let timeToSeek = TimeInterval(realPercent) * hasDuration
			seek(to: timeToSeek)
			return
		}
		if !rangeHeader {
			seek(to: hasDuration)
			return
		}
		//make offset and restart downloading
		offset = Int64(Float(totalSize) * percent)
		resumableData = ResumableData(offset: offset)
		restart()
	}

	public func restart() {
		let stateBefore = streamer.state
		streamer.reset()
		resume()
		if stateBefore == .playing {
			play()
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

	public func streamer(_ streamer: Streaming, fileFinished url: URL) {
		self.state = .ended
	}

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
        if self.totalSize < totalSize {
            self.totalSize = totalSize
        }
		self.rangeHeader = hasRangeHeader
	}
	
	public func streamer(_ streamer: Streaming, failedDownloadWithError error: Error, forURL url: URL, readyData bytes: Int64, response: URLResponse) {
		hasError = true
		resumableData = ResumableData(offset: offset, response: response, readyData: bytes)
		delegate?.player(self, failedDownloadWithError: error, forURL: url)
	}
	
	public func streamer(_ streamer: Streaming, updatedDownloadProgress progress: Float, bytesReceived bytes: Int64, forURL url: URL) {
		hasError = false
		hasBytes += bytes

		if progress == 1.0 && offset == 0 {
			fileDownloaded = true
		}
		let totalProgress = Float(hasBytes) / Float(totalSize)
		delegate?.player(self, updatedDownloadProgress: totalProgress, currentTaskProgress: progress, forURL: url)
		delegate?.player(self, updatedDuration: duration)
	}
	
	public func streamer(_ streamer: Streaming, changedState state: StreamingState) {
		amplitudes = [Float]()
		self.rate = self.baseRate
		switch state {
		case .paused:
			self.state = .paused
		case .playing:
			self.state = .playing
		case .stopped:
			self.state = .ready
		}
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
						let part = channelDataValueArray.map{ $0 * $0 }.reduce(0, +) / Float(buffer.frameLength)
						let rms = sqrt(part)
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
						let part = channelDataValueArray.map{ $0 * $0 }.reduce(0, +) / Float(buffer.frameLength)
						let rms = sqrt(part)
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
		hasDuration = duration
		delegate?.player(self, updatedDuration: self.duration)
	}
	
	public func streamer(_ streamer: Streaming, willProvideFormat format: AVAudioFormat?) {
		self.format = format
	}
}
