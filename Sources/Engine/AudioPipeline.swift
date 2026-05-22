//
//  AudioPipeline.swift
//  SomePlayer
//
//  Actor isolated to `AudioExecutor`. Owns long-running audio-side tasks
//  (scheduling tick, volume ramp, download consumer, command bodies) keyed
//  by purpose so a new task of the same kind cancels and replaces the
//  previous in-flight one.
//

import Foundation

public actor AudioPipeline {

    /// Identifies tasks owned by the pipeline so we can cancel and replace
    /// them one-at-a-time per kind. Internal kinds drive long-running loops
    /// (scheduling, downloader consumer); command kinds back the fire-and-
    /// forget public engine API — a new command of the same kind cancels
    /// any in-flight task with that key (audit-driven per-kind coalescing).
    public enum TaskKey: Hashable, Sendable {
        // Internal long-running loops
        case scheduling
        case volumeRamp
        case downloadConsumer

        // Public engine commands
        case play
        case pause
        case stop
        case seek
        case resume
        case restart
        case open
        case reset
        case setRate
        case setVolume
        case setPitch
        case setGlobalGain
        case setBaseRate
        case setSilenceHandling

        // Internal events that originate off-executor and need to land on it
        case tapPower
    }

    private let executor: AudioExecutor
    private var tasks: [TaskKey: Task<Void, Never>] = [:]

    public init(executor: AudioExecutor = AudioExecutor()) {
        self.executor = executor
    }

    public nonisolated var unownedExecutor: UnownedSerialExecutor {
        executor.asUnownedSerialExecutor()
    }

    /// Cancels any previous task with the same key and starts `work` as a
    /// new task isolated to this actor's executor. The closure runs on the
    /// audio queue; it is allowed to `await Task.sleep` for pacing but must
    /// avoid calling back into other actors (would reintroduce reentrancy).
    public func run(_ key: TaskKey, _ work: @escaping @Sendable () async -> Void) {
        tasks[key]?.cancel()
        tasks[key] = Task { await work() }
    }

    public func cancel(_ key: TaskKey) {
        tasks[key]?.cancel()
        tasks[key] = nil
    }

    public func cancelAll() {
        for task in tasks.values { task.cancel() }
        tasks.removeAll()
    }

    /// Cancels in-flight public command tasks but preserves the internal
    /// long-running loops (scheduling tick, downloader consumer, volume
    /// ramp). Used by `openRemote`/`openLocal`/`reset` to drop pending
    /// commands without taking down the playback pipeline itself.
    public func cancelPublicCommands() {
        let internalKinds: Set<TaskKey> = [.scheduling, .downloadConsumer, .volumeRamp]
        for (key, task) in tasks where !internalKinds.contains(key) {
            task.cancel()
            tasks[key] = nil
        }
    }

    /// One-shot hop onto the audio executor. Use for fire-and-forget
    /// fragments that need to run in the audio-serial domain (e.g., the
    /// `scheduleBuffer` completion handler) without holding a slot in the
    /// task map.
    public func perform(_ work: @Sendable () -> Void) {
        work()
    }

    /// Drives a periodic tick on the audio executor. `tick` runs synchronously
    /// on the pipeline's executor every `interval` until it returns `false`
    /// (signal to stop) or the task is cancelled. Replaces any previous
    /// scheduling task.
    public func startScheduling(interval: Duration, tick: @escaping @Sendable () -> Bool) {
        tasks[.scheduling]?.cancel()
        tasks[.scheduling] = Task { [weak self] in
            guard self != nil else { return }
            while !Task.isCancelled {
                if tick() == false { return }
                try? await Task.sleep(for: interval)
            }
        }
    }

    deinit {
        for task in tasks.values { task.cancel() }
    }
}
