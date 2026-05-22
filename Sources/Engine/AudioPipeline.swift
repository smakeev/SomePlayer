//
//  AudioPipeline.swift
//  SomePlayer
//
//  Actor isolated to `AudioExecutor`. Holds long-running audio-side Tasks
//  (scheduling tick, volume ramp, future download consumer, etc.) keyed by
//  purpose so a new task of the same kind cancels and replaces the previous.
//
//  Phase 2 introduces the actor with a minimal task-keeper API. Later phases
//  move parser/reader/scheduling state into the actor itself.
//
//  See THREADING_PLAN.md.
//

import Foundation

public actor AudioPipeline {

    /// Identifies long-running tasks owned by the pipeline so we can cancel
    /// and replace them one-at-a-time per kind.
    public enum TaskKey: Hashable, Sendable {
        case scheduling
        case volumeRamp
        case downloadConsumer
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
