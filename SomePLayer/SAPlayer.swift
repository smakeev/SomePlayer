//
//  SAPlayer.swift
//  SomePLayer
//
//  Created by Sergey Makeev on 17/06/2019.
//  Copyright © 2019 Sergey Makeev. All rights reserved.
//

import Foundation
import AVFoundation
import AudioStreamer

public protocol Engine: class {
	func getBaseRate() -> Float
	func setBaseRate(_ baseRate: Float)
	func leftChannel() -> Float?
	func rightChannel() -> Float?
	func buffer() -> AVAudioPCMBuffer?

	//handlers
}

open class SAPlayer {

	public struct SAPLayerItem {
		public var url:     URL!
		public var isLocal: Bool?

		public var title:  String?
		public var artist: String?
		public var album:  String?
		public var image:  UIImage?

		public var duration: TimeInterval

		init(url: URL,
			 isLocal:  Bool?    = nil,
			 title:    String?  = nil,
			 artist:   String?  = nil,
			 album:    String?  = nil,
			 image:    UIImage? = nil,
			 duration: TimeInterval = 0) {

			self.url      = url
			self.isLocal  = isLocal
			self.title    = title
			self.artist   = artist
			self.album    = album
			self.image    = image
			self.duration = duration

		}

		internal mutating func setTitle(_ title: String?) {
			self.title = title
		}

		internal mutating func setArtist(_ artist: String?) {
			self.artist = artist
		}

		internal mutating func setAlbum(_ album: String?) {
			self.album = album
		}

		internal mutating func setImage(_ image: UIImage?) {
			self.image = image
		}

		internal mutating func setDuration(_ duration: TimeInterval) {
			self.duration = duration
		}
	}

	public class SAPLayerItemRef {
		public var isCurrent: Bool = false

		init(_ item: SAPLayerItem) {
			self.item = item
		}
		public var item: SAPLayerItem
	}

	public enum SAPlayerState: Int {
		case undefined = 0
		case initializing
		case ready
		case playing
		case paused
		case ended
		case failed
	}

	final public class Queue {

	}

	public init() {
		playlist      = Queue()
		privateEngine = SomePlayerEngine()
		engine        = privateEngine as Engine
		state         = .undefined
		currentTime   = 0
	}

	public var volume: Float {
		get {
			return privateEngine.volume
		}

		set {
			privateEngine.volume = newValue
		}
	}

	public var rate: Float {
		get {
			return privateEngine.rate
		}

		set {
			privateEngine.baseRate = newValue
		}
	}

	public var pitch: Float {
		get {
			return privateEngine.pitch
		}
		set {
			privateEngine.pitch = newValue
		}
	}

	public internal(set) var state:       SAPlayerState!
	public internal(set) var currentItem: SAPLayerItemRef?
	public internal(set) var currentTime: TimeInterval
	public internal(set) var engine:      Engine!
	public internal(set) var playlist:    Queue!

	@discardableResult public func play() -> Bool {
		return false
	}

	@discardableResult public func playNext() -> Bool {
		return false
	}

	@discardableResult public func playPrev() -> Bool {
		return false
	}

	@discardableResult public func play(at index: UInt64) -> Bool {
		return false
	}

	@discardableResult public func pause() -> Bool {
		return false
	}

	@discardableResult public func stop() -> Bool {
		return false
	}

	@discardableResult public func seek(at time: TimeInterval) -> Bool {
		return false
	}

	@discardableResult public func seek(on time: TimeInterval) -> Bool {
		return false
	}

	//handlers

	internal var privateEngine: SomePlayerEngine!

	fileprivate func updateUI() {

	}
}

extension SomePlayerEngine: Engine {
	public func getBaseRate() -> Float {
		return self.baseRate
	}

	public func setBaseRate(_ baseRate: Float) {
		self.baseRate = baseRate
	}

	public func leftChannel() -> Float? {
		return self.averagePowerForChannel0
	}

	public func rightChannel() -> Float? {
		return self.averagePowerForChannel1
	}

	public func buffer() -> AVAudioPCMBuffer? {
		return self.lastBuffer
	}

}
