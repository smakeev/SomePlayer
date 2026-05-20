//
//  AdaptiveSpeedProcessing.swift
//  AudioStreamer
//
//  Created by OpenAI on 20/05/2026.
//

import Foundation

struct AdaptiveSpeedController {
    struct Decision {
        let targetRate: Float
        let maxRate: Float
        let maxStep: Float
        let smoothing: Float
    }

    private let maxBoost: Float = 0.55
    private let maxStep: Float = 0.035
    private let smoothing: Float = 0.14
    private let windowSize = 40
    private let minimumDynamicRange: Float = 8
    private let silenceCurvePower: Float = 2.8
    private let silenceScoreDeadZone: Float = 0.18

    private var loudnessWindow: [Float] = []

    mutating func reset() {
        loudnessWindow = []
    }

    mutating func decision(loudness: Float, baseRate: Float) -> Decision {
        loudnessWindow.append(loudness)
        if loudnessWindow.count > windowSize {
            loudnessWindow.removeFirst(loudnessWindow.count - windowSize)
        }

        guard loudnessWindow.count >= 4 else {
            return Decision(targetRate: baseRate, maxRate: baseRate + maxBoost, maxStep: maxStep, smoothing: smoothing)
        }

        let quietLevel = percentile(0.2, in: loudnessWindow)
        let speechLevel = percentile(0.8, in: loudnessWindow)
        let dynamicRange = max(speechLevel - quietLevel, minimumDynamicRange)
        let rawScore = (speechLevel - loudness) / dynamicRange
        let silenceScore = min(max(rawScore, 0), 1)
        let activeScore = min(max((silenceScore - silenceScoreDeadZone) / (1 - silenceScoreDeadZone), 0), 1)
        let curvedScore = powf(activeScore, silenceCurvePower)
        let targetRate = baseRate + maxBoost * curvedScore

        return Decision(targetRate: targetRate, maxRate: baseRate + maxBoost, maxStep: maxStep, smoothing: smoothing)
    }

    private func percentile(_ percentile: Float, in values: [Float]) -> Float {
        guard let first = values.first else { return 0 }
        guard values.count > 1 else { return first }

        let sortedValues = values.sorted()
        let index = Int(round(Float(sortedValues.count - 1) * percentile))
        return sortedValues[max(0, min(index, sortedValues.count - 1))]
    }
}
