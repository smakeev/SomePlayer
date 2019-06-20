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
		public var id: String { return idInternal.uuidString }
		public var anythingElse: Any?

		private var idInternal: UUID

		init(url: URL,
			 isLocal:  Bool?    = nil,
			 title:    String?  = nil,
			 artist:   String?  = nil,
			 album:    String?  = nil,
			 image:    UIImage? = nil,
			 duration: TimeInterval = 0,
			 anythingElse: Any? = nil) {

			self.url          = url
			self.isLocal      = isLocal
			self.title        = title
			self.artist       = artist
			self.album        = album
			self.image        = image
			self.duration     = duration
			self.anythingElse = anythingElse
			self.idInternal   = UUID()
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

		public enum QueueType {
			case general
			case playNext
			case sorted
			case randomized
		}

		public private(set) var type: QueueType = .general {
			didSet {
				onQueueType()
			}
		}

		public var count:         UInt = 0
		public var playNextCount: UInt = 0
		public var index:         UInt = 0

		public var first: SAPLayerItemRef?
		public var last:  SAPLayerItemRef?

		weak public var player: SAPlayer?

		init(_ player: SAPlayer) {
			self.player = player
		}

		public func itemForIndex(_ index: UInt) -> SAPLayerItemRef? {
			return nil
		}

		public func append(_ item: SAPLayerItemRef) {

		}

		public func push(_ item: SAPLayerItemRef) {

		}

		public func insert(at index: UInt, item: SAPLayerItemRef) {

		}

		public func remove(at index: UInt) {

		}

		public func remove(_ item: SAPLayerItemRef) {

		}

		public func removeLast() -> SAPLayerItemRef? {
			return nil
		}

		public func pop() -> SAPLayerItemRef? {
			return nil
		}

		public func randomize() {

		}

		public func sort(sortRule ascending: (SAPLayerItemRef, SAPLayerItemRef) -> Bool) {

		}

		public func restoreOrder() {

		}

		public func `switch`(index1: UInt, with index2: UInt) {

		}

		public func goNext() {

		}

		public func goBack() {

		}

		public func playNext(_ item: SAPLayerItemRef) {

		}

		public func removeFromPlayNext(_ item: SAPLayerItemRef) {

		}

		public func clearPlayNext() {

		}

		public func next(onChange observer: AnyObject?, handler: @escaping (Queue) -> Void) {

		}

		public func once(onChange observer: AnyObject?, handler: @escaping (Queue) -> Void) {

		}

		public func unsubscribe(onChange observer: AnyObject?) {

		}

		public func next(willGoNext observer: AnyObject?, handler: @escaping (Queue) -> Void) {

		}

		public func once(willGoNext observer: AnyObject?, handler: @escaping (Queue) -> Void) {

		}

		public func unsubscribe(willGoNext observer: AnyObject?) {

		}

		public func next(wentNext observer: AnyObject?, handler: @escaping (Queue) -> Void) {

		}

		public func once(wentNext observer: AnyObject?, handler: @escaping (Queue) -> Void) {

		}

		public func unsubscribe(wentNext observer: AnyObject?) {

		}

		public func next(type observer: AnyObject?, handler: @escaping (QueueType) -> Void) {

		}

		public func once(type observer: AnyObject?, handler: @escaping (QueueType) -> Void) {

		}

		public func unsubscribe(type observer: AnyObject?) {

		}


		public func unsubscribe(_ observer: AnyObject?) {

		}

		private func onChange() {
			onChangeDispatcher.dispatch(self)
		}

		private func onWillGoNext() {
			onWillGoNextDispatcher.dispatch(self)
		}

		private func onWentNext() {
			onWenNexDispatcher.dispatch(self)
		}

		private func onQueueType() {
			onTypeDispatcher.dispatch(type)
		}

		private var onChangeDispatcher     = Dispatcher<Queue>()
		private var onWillGoNextDispatcher = Dispatcher<Queue>()
		private var onWenNexDispatcher     = Dispatcher<Queue>()
		private var onTypeDispatcher       = Dispatcher<QueueType>()

		private var playNextItems = [SAPLayerItemRef]()
		private var items         = [SAPLayerItemRef]()
		private var orderedItems  = [SAPLayerItemRef]()
	}

	public init() {
		privateEngine = SomePlayerEngine()
		engine        = privateEngine as Engine
		state         = .undefined
		playlist      = Queue(self)
	}

	public var background:    Bool = false {
		didSet {

		}
	}

	public var controlCenter: Bool = false {
		didSet {

		}
	}

	public var carPLay:       Bool = false {
		didSet {

		}
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
	public var currentTime: TimeInterval {
		get {
			return privateEngine.currentTime + timeOffset
		}
	}
	public internal(set) var engine:      Engine!
	public internal(set) var playlist:    Queue!
	public var timeOffset: TimeInterval {
		get {
			return privateEngine.timeOffset
		}
	}

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
	public func setSmartSpeed(_ activate: Bool) {

	}

	public func setSilenceSpeedUp(_ activate: Bool) {

	}

	//handlers

	public func next(onTimeOffset observer: AnyObject?, handler: @escaping (TimeInterval) -> Void) {

	}

	public func once(onTimeOffset observer: AnyObject?, handler: @escaping (TimeInterval) -> Void) {

	}

	public func unsubscribe(onTimeOfset observer: AnyObject?) {

	}

	public func next(onBackground observer: AnyObject?, handler: @escaping (Bool) -> Void) {

	}

	public func once(onBackground observer: AnyObject?, handler: @escaping (Bool) -> Void) {

	}

	public func unsubscribe(onBackground observer: AnyObject?) {

	}

	public func next(onCarPlay observer: AnyObject?, handler: @escaping (Bool) -> Void) {

	}

	public func once(onCarPlay observer: AnyObject?, handler: @escaping (Bool) -> Void) {

	}

	public func unsubscribe(onCarPlay observer: AnyObject?) {

	}

	public func next(onControllCenter observer: AnyObject?, handler: @escaping (Bool) -> Void) {

	}

	public func once(onControllCenter observer: AnyObject?, handler: @escaping (Bool) -> Void) {

	}

	public func unsubscribe(onControllCenter observer: AnyObject?) {

	}

	public func next(onVolume observer: AnyObject?, handler: @escaping (Float) -> Void) {

	}

	public func once(onVolume observer: AnyObject?, handler: @escaping (Float) -> Void) {

	}

	public func unsubscribe(onVolume observer: AnyObject?) {

	}

	public func next(onRate observer: AnyObject?, handler: @escaping (Float) -> Void) {

	}

	public func once(onRate observer: AnyObject?, handler: @escaping (Float) -> Void) {

	}

	public func unsubscribe(onRate observer: AnyObject?) {

	}

	public func next(onPitch observer: AnyObject?, handler: @escaping (Float) -> Void) {

	}

	public func once(onPitch observer: AnyObject?, handler: @escaping (Float) -> Void) {

	}

	public func unsubscribe(onPitch observer: AnyObject?) {

	}

	public func next(onState observer: AnyObject?, handler: @escaping (SAPlayerState) -> Void) {

	}

	public func once(onState observer: AnyObject?, handler: @escaping (SAPlayerState) -> Void) {

	}

	public func unsubscribe(onState observer: AnyObject?) {

	}

	public func next(onCurrentItem observer: AnyObject?, handler: @escaping (SAPLayerItemRef?) -> Void) {

	}

	public func once(onCurrentItem observer: AnyObject?, handler: @escaping (SAPLayerItemRef?) -> Void) {

	}

	public func unsubscribe(onCurrentItem observer: AnyObject?) {

	}

	public func next(onPlaylist observer: AnyObject?, handler: @escaping (Queue) -> Void) {

	}

	public func once(onPlaylist observer: AnyObject?, handler: @escaping (Queue) -> Void) {

	}

	public func unsubscribe(onPlaylist observer: AnyObject?) {

	}

	public func next(onTime observer: AnyObject?, handler: @escaping (TimeInterval) -> Void) {

	}

	public func unsubscribe(onTime observer: AnyObject?) {

	}

	public func once(onTime observer: AnyObject?, handler: @escaping (TimeInterval) -> Void) {

	}

	public func next(onSecondsSaved observer: AnyObject?, handler: @escaping (TimeInterval) -> Void) {

	}

	public func once(onSecondsSaved observer: AnyObject?, handler: @escaping (TimeInterval) -> Void) {

	}

	public func unsubscribe(onSecondsSaved observer: AnyObject?) {

	}

	public func next(onDuration observer: AnyObject?, handler: @escaping (TimeInterval) -> Void) {

	}

	public func once(onDuration observer: AnyObject?, handler: @escaping (TimeInterval) -> Void) {

	}

	public func unsubscribe(onDuration observer: AnyObject?) {

	}

	public func once(onDownloadProgress observer: AnyObject?, handler: @escaping (Float) -> Void) {

	}

	public func next(onDownloadProgress observer: AnyObject?, handler: @escaping (Float) -> Void) {

	}

	public func unsubscribe(onDownloadProgress observer: AnyObject?) {

	}

	public func next(onItemFinished observer: AnyObject?, handler : @escaping (SAPLayerItemRef) -> Void) {

	}

	public func once(onItemFinished observer: AnyObject?, handler : @escaping (SAPLayerItemRef) -> Void) {

	}

	public func unsubscribe(onItemFinished observer: AnyObject?) {

	}

	public func next(onLeftChannel observer: AnyObject?, handler : @escaping (Float?) -> Void) {

	}

	public func once(onLeftChannel observer: AnyObject?, handler : @escaping (Float?) -> Void) {

	}

	public func unsubscribe(onLeftChannel observer: AnyObject?) {

	}

	public func next(onRightChannel observer: AnyObject?, handler : @escaping (Float?) -> Void) {

	}

	public func once(onRightChannel observer: AnyObject?, handler : @escaping (Float?) -> Void) {

	}

	public func unsubscribe(onRightChannel observer: AnyObject?) {

	}

	public func next(onBuffer observer: AnyObject?, handler : @escaping (Float?) -> Void) {

	}

	public func once(onBuffer observer: AnyObject?, handler : @escaping (Float?) -> Void) {

	}

	public func unsubscribe(onBuffer observer: AnyObject?) {

	}

	public func next(onDownloadCompleted observer: AnyObject?, handler : @escaping (SAPlayer) -> Void) {

	}

	public func once(onDownloadCompleted observer: AnyObject?, handler : @escaping (SAPlayer) -> Void) {

	}

	public func unsubscribe(onDownloadCompleted observer: AnyObject?) {

	}

	public func next(onSmartSpeed observer: AnyObject?, handler : @escaping (Bool) -> Void) {

	}

	public func once(onSmartSpeed observer: AnyObject?, handler : @escaping (Bool) -> Void) {

	}

	public func unsubscribe(onSmartSpeed observer: AnyObject?) {

	}

	public func next(onSilenceSpeedUp observer: AnyObject?, handler : @escaping (Bool) -> Void) {

	}

	public func once(onSilenceSpeedUp observer: AnyObject?, handler : @escaping (Bool) -> Void) {

	}

	public func unsubscribe(onSilenceSpeedUp observer: AnyObject?) {

	}

	public func unsubscribe(_ observer: AnyObject?) {

	}

	internal var privateEngine: SomePlayerEngine!

	fileprivate var onBackgroundDispatcher        = Dispatcher<Bool>()
	fileprivate var onCarPlayDispatcher           = Dispatcher<Bool>()
	fileprivate var onControllCenterDispatcher    = Dispatcher<Bool>()
	fileprivate var onVolumeDispatcher            = Dispatcher<Float>()
	fileprivate var onRateDispatcher              = Dispatcher<Float>()
	fileprivate var onPitchDispatcher             = Dispatcher<Float>()
	fileprivate var onStateDispatcher             = Dispatcher<SAPlayerState>()
	fileprivate var onCurrentItemDispatcher       = Dispatcher<SAPLayerItemRef>()
	fileprivate var onPlaylistDispatcher          = Dispatcher<Queue>()
	fileprivate var onTimeDispatcher              = Dispatcher<TimeInterval>()
	fileprivate var onSecondsSavedDispatcher      = Dispatcher<TimeInterval>()
	fileprivate var onDurationSavedDispatcher     = Dispatcher<TimeInterval>()
	fileprivate var onDownloadProgressDispatcher  = Dispatcher<Float>()
	fileprivate var onTimeOffsetDispatcher        = Dispatcher<TimeInterval>()
	fileprivate var onItemFinishedDispatcher      = Dispatcher<SAPLayerItemRef>()
	fileprivate var onLeftChannelDispatcher       = Dispatcher<Float?>()
	fileprivate var onRightChannelDispatcher      = Dispatcher<Float?>()
	fileprivate var onBufferDispatcher            = Dispatcher<AVAudioPCMBuffer?>()
	fileprivate var onDownloadCompletedDispatcher = Dispatcher<SAPlayer>()
	fileprivate var onSmartSpeedDispatcher        = Dispatcher<Bool>()
	fileprivate var onSilenceSpeedUpDispatcher    = Dispatcher<Bool>()
}

//onEvents reactions
extension SAPlayer {

	fileprivate func onTimeOfset() {
		onTimeDispatcher.dispatch(timeOffset)
	}

	fileprivate func onVolume() {
		onVolumeDispatcher.dispatch(volume)
	}

	fileprivate func onRate() {
		onRateDispatcher.dispatch(rate)
	}

	fileprivate func onPitch() {
		onPitchDispatcher.dispatch(pitch)
	}

	fileprivate func onState() {
		onStateDispatcher.dispatch(state)
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

	fileprivate func onDownloadComplete() {

	}

	fileprivate func onItemFinished(_ item: SAPLayerItemRef) {

	}

	fileprivate func onBuffer(_ buffer: AVAudioPCMBuffer?) {

	}

	fileprivate func onLeftChannel(_ averageValue: Float?) {

	}

	fileprivate func onRightChannel(_ averagevalue: Float?) {

	}

	fileprivate func onCurrentItemElements() {

	}

	fileprivate func onSmartSpeed() {

	}

	fileprivate func onSilenceSpeedUp() {

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
