//
//  SilenceProcessing.swift
//  AudioStreamer
//
//  Created by OpenAI on 20/05/2026.
//

import AVFoundation
import Foundation

struct SilencePowerLevels {
	let combined: Float
	let channel0: Float?
	let channel1: Float?
	let frameLength: AVAudioFrameCount
}

struct SilenceAudioAnalyzer {
	private static let minimumRMS: Float = 0.000001

	static func powerLevels(from buffer: AVAudioPCMBuffer) -> SilencePowerLevels? {
		let frameLength = buffer.frameLength
		guard frameLength > 0,
			  buffer.format.channelCount > 0,
			  let channelData = buffer.floatChannelData else {
			return nil
		}

		let channelCount = Int(buffer.format.channelCount)
		var totalSquares: Float = 0
		var totalSampleCount = 0
		var channelPowers: [Float] = []

		for channelIndex in 0..<channelCount {
			let channelSamples = channelData[channelIndex]
			var channelSquares: Float = 0
			var channelSampleCount = 0
			var frameIndex = 0

			while frameIndex < Int(frameLength) {
				let sample = channelSamples[frameIndex]
				channelSquares += sample * sample
				channelSampleCount += 1
				frameIndex += buffer.stride
			}

			if channelSampleCount > 0 {
				totalSquares += channelSquares
				totalSampleCount += channelSampleCount
				channelPowers.append(decibels(fromMeanSquare: channelSquares / Float(channelSampleCount)))
			}
		}

		guard totalSampleCount > 0 else { return nil }

		return SilencePowerLevels(
			combined: decibels(fromMeanSquare: totalSquares / Float(totalSampleCount)),
			channel0: channelPowers.first,
			channel1: channelPowers.count > 1 ? channelPowers[1] : channelPowers.first,
			frameLength: frameLength
		)
	}

	private static func decibels(fromMeanSquare meanSquare: Float) -> Float {
		let rms = max(sqrt(meanSquare), minimumRMS)
		return 20 * log10(rms)
	}
}

struct SilenceRateController {
	enum Mode {
		case none
		case smart
		case speedUp
	}

	struct Decision {
		let targetRate: Float
		let maxRate: Float
		let shouldReportSavedTime: Bool
	}

	private let smartMaxBoost: Float = 0.75
	private let speedUpRate: Float = 3
	private let silenceEnterThreshold: Float = -38
	private let silenceExitThreshold: Float = -32
	private let silenceEnterBuffers = 3
	private let silenceExitBuffers = 2
	private let smartWindowSize = 20
	private let smartLoudnessSmoothing: Float = 0.35

	private var isSilent = false
	private var silentBufferCount = 0
	private var speechBufferCount = 0
	private var smoothedLoudness: Float?
	private var smartAmplitudes: [Float] = []

	mutating func reset() {
		isSilent = false
		silentBufferCount = 0
		speechBufferCount = 0
		smoothedLoudness = nil
		smartAmplitudes = []
	}

	mutating func decision(
		for mode: Mode,
		loudness: Float?,
		baseRate: Float,
		globalGain: Float
	) -> Decision? {
		guard mode != .none else {
			reset()
			return Decision(targetRate: baseRate, maxRate: max(baseRate, speedUpRate), shouldReportSavedTime: false)
		}
		guard let loudness = loudness, loudness.isFinite else { return nil }

		updateSilenceState(with: loudness)

		switch mode {
		case .none:
			return nil
		case .speedUp:
			let targetRate = isSilent ? speedUpRate : baseRate
			return Decision(
				targetRate: targetRate,
				maxRate: max(baseRate, speedUpRate),
				shouldReportSavedTime: targetRate > baseRate
			)
		case .smart:
			let targetRate = smartTargetRate(loudness: loudness, baseRate: baseRate, globalGain: globalGain)
			return Decision(
				targetRate: targetRate,
				maxRate: baseRate + smartMaxBoost,
				shouldReportSavedTime: targetRate > baseRate
			)
		}
	}

	private mutating func updateSilenceState(with loudness: Float) {
		if isSilent {
			if loudness > silenceExitThreshold {
				speechBufferCount += 1
			} else {
				speechBufferCount = 0
			}

			if speechBufferCount >= silenceExitBuffers {
				isSilent = false
				speechBufferCount = 0
				silentBufferCount = 0
			}
		} else {
			if loudness < silenceEnterThreshold {
				silentBufferCount += 1
			} else {
				silentBufferCount = 0
			}

			if silentBufferCount >= silenceEnterBuffers {
				isSilent = true
				silentBufferCount = 0
				speechBufferCount = 0
			}
		}
	}

	private mutating func smartTargetRate(loudness: Float, baseRate: Float, globalGain: Float) -> Float {
		let currentLoudness: Float
		if let previous = smoothedLoudness {
			currentLoudness = previous + (loudness - previous) * smartLoudnessSmoothing
		} else {
			currentLoudness = loudness
		}
		smoothedLoudness = currentLoudness

		let currentAmplitude = currentLoudness + 120
		smartAmplitudes.append(currentAmplitude)
		if smartAmplitudes.count > smartWindowSize {
			smartAmplitudes.removeFirst(smartAmplitudes.count - smartWindowSize)
		}
		guard smartAmplitudes.count >= silenceEnterBuffers else { return baseRate }

		let referenceAmplitude = percentile(0.8, in: smartAmplitudes)
		let amplitudeGap = max(0, referenceAmplitude - currentAmplitude)
		let multiplier: Float

		if currentAmplitude > 100 + globalGain {
			multiplier = 0
		} else if isSilent || currentAmplitude <= 50 + globalGain {
			multiplier = 0.02
		} else {
			multiplier = 0.01
		}

		return baseRate + amplitudeGap * multiplier
	}

	private func percentile(_ percentile: Float, in values: [Float]) -> Float {
		guard let first = values.first else { return 0 }
		guard values.count > 1 else { return first }

		let sortedValues = values.sorted()
		let index = Int(round(Float(sortedValues.count - 1) * percentile))
		return sortedValues[max(0, min(index, sortedValues.count - 1))]
	}
}
