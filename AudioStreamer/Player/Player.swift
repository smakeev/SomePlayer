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
}


open class SomePlayer: NSObject {

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
        streamer.play()
    }

    public func seek(to time: TimeInterval) {
        do{
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

    public var rate: Float {
        get {
            return streamer.rate
        }
        set {
            print("rate: \(newValue))")
            streamer.rate = newValue
        }
    }

    private var amplitudes: [Float] = [Float]()

    private func handleSilence() {
        let defaultPLaybackRate: Float = 1

//////////////////begin 1
//        let decibelThreshold = Float(-35)
//
//        let sampleRate = 0.1
//        let skippedSeconds = 0.0
//
//        if let average = averagePowerForChannel0 {
//            if average < decibelThreshold {
//                self.rate = 3
//            } else {
//                self.rate = Float(defaultPLaybackRate)
//            }
//        }
///////end 1

////////////////////begin2
        guard let average = self.averagePowerForChannel0 else { return }
        amplitudes.append(average + 120)
        if self.amplitudes.last! > 50 {
            self.rate = defaultPLaybackRate + (amplitudes.max()! - amplitudes.last!) * 0.01
        } else {
            self.rate = defaultPLaybackRate + (amplitudes.max()! - amplitudes.last!) * 0.02
        }

    }

    public fileprivate(set) var averagePowerForChannel0: Float? = nil {
        didSet {
            //print("CH0 \(String(describing: averagePowerForChannel0))")
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


    public func streamer(_ streamer: Streaming, failedDownloadWithError error: Error, forURL url: URL) {
        delegate?.player(self, failedDownloadWithError: error, forURL: url)
    }

    public func streamer(_ streamer: Streaming, updatedDownloadProgress progress: Float, forURL url: URL) {
        delegate?.player(self, updatedDownloadProgress: progress, forURL: url)
    }

    public func streamer(_ streamer: Streaming, changedState state: StreamingState) {
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
