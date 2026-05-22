//
//  AudioExecutor.swift
//  SomePlayer
//
//  Custom `SerialExecutor` backed by a dedicated dispatch queue. Used as
//  the isolation domain for `AudioPipeline`. Pins all engine-side audio
//  work to one serial queue so AVAudioEngine config, C callbacks, and
//  scheduling run off-main and in a deterministic order.
//

import Foundation

public final class AudioExecutor: SerialExecutor, @unchecked Sendable {
    private let queue: DispatchQueue

    public init(label: String = "com.someplayer.engine.audio") {
        self.queue = DispatchQueue(label: label, qos: .userInitiated)
    }

    public func enqueue(_ job: consuming ExecutorJob) {
        let unowned = UnownedJob(job)
        let executor = asUnownedSerialExecutor()
        queue.async {
            unowned.runSynchronously(on: executor)
        }
    }

    public func asUnownedSerialExecutor() -> UnownedSerialExecutor {
        UnownedSerialExecutor(ordinary: self)
    }
}
