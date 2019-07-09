//
//  TimePitchStreamer.swift
//  TimePitchStreamer
//
//  Created by Syed Haris Ali on 6/5/18.
//

import Foundation
import AVFoundation

/// The `TimePitchStreamer` demonstrates how to subclass the `Streamer` and add a time/pitch shift effect.
public class TimePitchStreamer: Streamer {

	/// An `AVAudioUnitTimePitch` used to perform the time/pitch shift effect
	public let timePitchNode  = AVAudioUnitTimePitch()

	public let voiceBoostNode = AVAudioUnitEQ()

	/// A `Float` representing the pitch of the audio
	public var pitch: Float {
		get {
			return timePitchNode.pitch
		}
		set {
			timePitchNode.pitch = newValue
		}
	}

	/// A `Float` representing the playback rate of the audio
	public var rate: Float {
		get {
			return timePitchNode.rate
		}
		set {
			timePitchNode.rate = newValue
		}
	}

	public var globalGain: Float {
		get {
			return voiceBoostNode.globalGain
		}

		set {
			guard newValue >= -96 && newValue <= 24 else { return }
			voiceBoostNode.globalGain = newValue
		}
	}

	// MARK: - Methods

	override public func attachNodes() {
		super.attachNodes()
		engine.attach(timePitchNode)
		engine.attach(voiceBoostNode)
	}

	override public func connectNodes() {
		engine.connect(playerEngineNode, to: timePitchNode, format: readFormat)
		engine.connect(timePitchNode,  to: voiceBoostNode, format: readFormat)
		engine.connect(voiceBoostNode, to: engine.mainMixerNode, format: readFormat)
	}

}
