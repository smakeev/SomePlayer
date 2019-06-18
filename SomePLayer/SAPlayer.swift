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
			observer?.onCurrentItemElements()
		}

		internal mutating func setArtist(_ artist: String?) {
			self.artist = artist
			observer?.onCurrentItemElements()
		}

		internal mutating func setAlbum(_ album: String?) {
			self.album = album
			observer?.onCurrentItemElements()
		}

		internal mutating func setImage(_ image: UIImage?) {
			self.image = image
			observer?.onCurrentItemElements()
		}

		internal mutating func setDuration(_ duration: TimeInterval) {
			self.duration = duration
			observer?.onCurrentItemElements()
		}

		fileprivate mutating func subscribe(_ observer: SAPlayer?) {
			self.observer = observer
			observer?.onCurrentItemElements()
		}

		private weak var observer: SAPlayer?
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


		public func each(onChange observer: AnyObject?, handler: @escaping (Queue) -> Void) {

		}

		public func once(onChange observer: AnyObject?, handler: @escaping (Queue) -> Void) {

		}

		public func unsubscribe(onChange observer: AnyObject?) {

		}

		public func each(willGoNext observer: AnyObject?, handler: @escaping (Queue) -> Void) {

		}

		public func once(willGoNext observer: AnyObject?, handler: @escaping (Queue) -> Void) {

		}

		public func unsubscribe(willGoNext observer: AnyObject?) {

		}

		public func each(wentNext observer: AnyObject?, handler: @escaping (Queue) -> Void) {

		}

		public func once(wentNext observer: AnyObject?, handler: @escaping (Queue) -> Void) {

		}

		public func unsubscribe(wentNext observer: AnyObject?) {

		}

		public func unsubscribe(_ observer: AnyObject?) {

		}

		private func onChange() {

		}

		private func willGoNext() {

		}

		private func wentNext() {

		}
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

	//effects:


	//handlers

	public func each(onVolume observer: AnyObject?, handler: @escaping (Float) -> Void) {

	}

	public func once(onVolume observer: AnyObject?, handler: @escaping (Float) -> Void) {

	}

	public func unsubscribe(onVolume observer: AnyObject?) {

	}

	public func each(onRate observer: AnyObject?, handler: @escaping (Float) -> Void) {

	}

	public func once(onRate observer: AnyObject?, handler: @escaping (Float) -> Void) {

	}

	public func unsubscribe(onRate observer: AnyObject?) {

	}

	public func each(onPitch observer: AnyObject?, handler: @escaping (Float) -> Void) {

	}

	public func once(onPitch observer: AnyObject?, handler: @escaping (Float) -> Void) {

	}

	public func unsubscribe(onPitch observer: AnyObject?) {

	}

	public func each(onState observer: AnyObject?, handler: @escaping (SAPlayerState) -> Void) {

	}

	public func once(onState observer: AnyObject?, handler: @escaping (SAPlayerState) -> Void) {

	}

	public func unsubscribe(onState observer: AnyObject?) {

	}

	public func each(onCurrentItem observer: AnyObject?, handler: @escaping (SAPLayerItemRef?) -> Void) {

	}

	public func once(onCurrentItem observer: AnyObject?, handler: @escaping (SAPLayerItemRef?) -> Void) {

	}

	public func unsubscribe(onCurrentItem observer: AnyObject?) {

	}

	public func each(oPlaylist observer: AnyObject?, handler: @escaping (Queue) -> Void) {

	}

	public func once(onPlaylist observer: AnyObject?, handler: @escaping (Queue) -> Void) {

	}

	public func unsubscribe(oPlaylist observer: AnyObject?) {

	}

	public func each(onTime observer: AnyObject?, handler: @escaping (TimeInterval) -> Void) {

	}

	public func unsubscribe(onTime observer: AnyObject?) {

	}

	public func once(onTime observer: AnyObject?, handler: @escaping (TimeInterval) -> Void) {

	}

	public func each(onSecondsSaved observer: AnyObject?, handler: @escaping (TimeInterval) -> Void) {

	}

	public func once(onSecondsSaved observer: AnyObject?, handler: @escaping (TimeInterval) -> Void) {

	}

	public func unsubscribe(onSecondsSaved observer: AnyObject?) {

	}

	public func each(onDuration observer: AnyObject?, handler: @escaping (TimeInterval) -> Void) {

	}

	public func once(onDuration observer: AnyObject?, handler: @escaping (TimeInterval) -> Void) {

	}

	public func unsubscribe(onDuration observer: AnyObject?) {

	}

	public func once(onDownloadProgress observer: AnyObject?, handler: @escaping (Float) -> Void) {

	}

	public func each(onDownloadProgress observer: AnyObject?, handler: @escaping (Float) -> Void) {

	}

	public func unsubscribe(onDownloadProgress observer: AnyObject?) {

	}

	public func each(onItemFinished observer: AnyObject?, handler : @escaping () -> Void) {

	}

	public func once(onItemFinished observer: AnyObject?, handler : @escaping () -> Void) {

	}

	public func unsubscribe(onItemFinished observer: AnyObject?) {

	}

	public func each(onLeftChannel observer: AnyObject?, handler : @escaping () -> Void) {

	}

	public func once(onLeftChannel observer: AnyObject?, handler : @escaping () -> Void) {

	}

	public func unsubscribe(onLeftChannel observer: AnyObject?) {

	}

	public func each(onRightChannel observer: AnyObject?, handler : @escaping () -> Void) {

	}

	public func once(onRightChannel observer: AnyObject?, handler : @escaping () -> Void) {

	}

	public func unsubscribe(onRightChannel observer: AnyObject?) {

	}

	public func each(onBufferChannel observer: AnyObject?, handler : @escaping () -> Void) {

	}

	public func once(onBufferChannel observer: AnyObject?, handler : @escaping () -> Void) {

	}

	public func unsubscribe(onBufferChannel observer: AnyObject?) {

	}

	public func unsubscribe(_ observer: AnyObject?) {

	}

	internal var privateEngine: SomePlayerEngine!

	fileprivate func updateUI() {

	}
}

//onEvents reactions
extension SAPlayer {

	fileprivate func onVolume() {

	}

	fileprivate func onRate() {

	}

	fileprivate func onPitch() {

	}

	fileprivate func onState() {

	}

	fileprivate func onCurrentItem() {

	}

	fileprivate func onPlayList() {

	}

	fileprivate func onTime() {

	}

	fileprivate func onSecondsSaved() {

	}

	fileprivate func onDuration() {

	}

	fileprivate func onDownloadProgress() {

	}

	fileprivate func onItemFinished() {

	}

	fileprivate func onBuffer(_ buffer: AVAudioPCMBuffer?) {

	}

	fileprivate func onLeftChannel(_ averageValue: Float?) {

	}

	fileprivate func onRightChannel(_ averagevalue: Float?) {

	}

	fileprivate func onCurrentItemElements() {

	}
	//onSmartSpeed


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
