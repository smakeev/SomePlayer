//
//  DelegateEmitter.swift
//  SomePlayer
//
//  @MainActor throttled delivery of `SomeplayerEngineDelegate` callbacks.
//
//  Pattern:
//    - Engine code calls `enqueueXxx(...)` from any thread (`nonisolated`,
//      lock-protected; no thread-hop, no allocation in the hot path).
//    - A single `Task.sleep` loop on `@MainActor` drains pending events
//      every ~100 ms and fires per-event-type delegate calls.
//    - Scalar high-frequency fields (time/duration/progress/rate/etc.) are
//      coalesce-latest: only the most recent value is delivered per tick.
//    - Edge-triggered events (state, errors, seek-failed) are FIFO and
//      never coalesced or dropped.
//

import Foundation
import os

/// All pending notifications since the last `flush()`. Cleared atomically
/// when the emitter drains it.
struct PendingEvents: Sendable {
    // Coalesce-latest scalar fields. Last setter wins; only one delegate
    // call per field per tick.
    var time: TimeInterval?
    var duration: TimeInterval?
    var downloadProgress: (progress: Float, taskProgress: Float, url: URL)?
    var savedSeconds: TimeInterval?
    var buffering: Bool?
    var waitingForDownloader: Bool?
    var offset: Int64?
    var title: String?
    var artist: String?
    var album: String?
    var image: SomePlayerImage?

    // Edge events fire in FIFO order, one delegate call each.
    var edgeEvents: [PlayerEvent] = []

    var isEmpty: Bool {
        time == nil && duration == nil && downloadProgress == nil
            && savedSeconds == nil && buffering == nil
            && waitingForDownloader == nil && offset == nil
            && title == nil && artist == nil && album == nil && image == nil
            && edgeEvents.isEmpty
    }
}

@MainActor
public final class DelegateEmitter {

    /// Tick interval for the drain loop. ~10 Hz is comfortably faster than
    /// any UI repaint cadence and slow enough to amortise main-thread cost.
    static let tickInterval: Duration = .milliseconds(100)

    // Engine sets `engine` once at construction; `delegate` may be set from
    // any thread via the engine's `delegate` didSet. Read on MainActor in
    // `flush`. Weak refs serialise via the runtime's weak-ref atomicity;
    // marked `nonisolated(unsafe)` to skip an extra Task hop on set.
    nonisolated(unsafe) weak var delegate: SomeplayerEngineDelegate?
    nonisolated(unsafe) weak var engine: SomePlayerEngine?

    private let pending = OSAllocatedUnfairLock<PendingEvents>(initialState: PendingEvents())
    private var emitterTask: Task<Void, Never>?

    /// Nonisolated init so callers can construct an emitter from any
    /// context (e.g., a non-MainActor `SomePlayerEngine.init`). All the
    /// MainActor-isolated work (`start`, `flush`) happens later.
    public nonisolated init() {}

    /// Starts the drain loop. Safe to call multiple times; subsequent calls are no-ops.
    func start() {
        guard emitterTask == nil else { return }
        emitterTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self = self else { return }
                self.flush()
                try? await Task.sleep(for: Self.tickInterval)
            }
        }
    }

    func stop() {
        emitterTask?.cancel()
        emitterTask = nil
    }

    deinit {
        emitterTask?.cancel()
    }

    // MARK: - Nonisolated enqueue (callable from any thread)

    public nonisolated func enqueueTime(_ value: TimeInterval) {
        pending.withLock { $0.time = value }
    }
    public nonisolated func enqueueDuration(_ value: TimeInterval) {
        pending.withLock { $0.duration = value }
    }
    public nonisolated func enqueueDownloadProgress(progress: Float, taskProgress: Float, url: URL) {
        pending.withLock { $0.downloadProgress = (progress, taskProgress, url) }
    }
    public nonisolated func enqueueSavedSeconds(_ value: TimeInterval) {
        pending.withLock { $0.savedSeconds = value }
    }
    public nonisolated func enqueueBuffering(_ value: Bool) {
        pending.withLock { $0.buffering = value }
    }
    public nonisolated func enqueueWaitingForDownloader(_ value: Bool) {
        pending.withLock { $0.waitingForDownloader = value }
    }
    public nonisolated func enqueueOffset(_ value: Int64) {
        pending.withLock { $0.offset = value }
    }
    public nonisolated func enqueueTitle(_ value: String) {
        pending.withLock { $0.title = value }
    }
    public nonisolated func enqueueArtist(_ value: String) {
        pending.withLock { $0.artist = value }
    }
    public nonisolated func enqueueAlbum(_ value: String) {
        pending.withLock { $0.album = value }
    }
    public nonisolated func enqueueImage(_ value: SomePlayerImage) {
        pending.withLock { $0.image = value }
    }

    /// Edge-triggered events fire FIFO and are never coalesced. Reserved for
    /// state changes, errors, file-finished, failures, seek-failed.
    public nonisolated func enqueueEdge(_ event: PlayerEvent) {
        pending.withLock { $0.edgeEvents.append(event) }
    }

    // MARK: - Flush (MainActor)

    private func flush() {
        let snapshot = pending.withLock { events -> PendingEvents in
            let s = events
            events = PendingEvents()
            return s
        }
        guard !snapshot.isEmpty, let engine = engine else { return }
        let delegate = self.delegate

        // Edge events first, in FIFO order.
        for event in snapshot.edgeEvents {
            dispatchEdge(event, engine: engine, delegate: delegate)
        }

        // Then coalesced scalar fields.
        if let v = snapshot.title  { delegate?.playerEngine(engine, changedTitle: v) }
        if let v = snapshot.artist { delegate?.playerEngine(engine, changedArtist: v) }
        if let v = snapshot.album  { delegate?.playerEngine(engine, changedAlbum: v) }
        if let v = snapshot.image  { delegate?.playerEngine(engine, changedImage: v) }
        if let v = snapshot.offset { delegate?.playerEngine(engine, offsetChanged: v) }
        if let v = snapshot.buffering {
            delegate?.playerEngine(engine, isBuffering: v)
        }
        if let v = snapshot.waitingForDownloader {
            delegate?.playerEngine(engine, isWaitingForDownloader: v)
        }
        if let v = snapshot.time     { delegate?.playerEngine(engine, updatedCurrentTime: v) }
        if let v = snapshot.duration { delegate?.playerEngine(engine, updatedDuration: v) }
        if let v = snapshot.downloadProgress {
            delegate?.playerEngine(engine,
                                   updatedDownloadProgress: v.progress,
                                   currentTaskProgress: v.taskProgress,
                                   forURL: v.url)
        }
        if let v = snapshot.savedSeconds { delegate?.playerEngine(engine, savedSeconds: v) }
    }

    private func dispatchEdge(_ event: PlayerEvent,
                              engine: SomePlayerEngine,
                              delegate: SomeplayerEngineDelegate?) {
        switch event {
        case .stateChanged(let s):
            delegate?.playerEngine(engine, changedState: s)
        case .failure(let f):
            delegate?.playerEngine(engine, failedWithException: f)
        case .seekFailed(let e):
            delegate?.playerEngine(engine, seekFailed: e)
        case .downloadFailed(let e, let u):
            delegate?.playerEngine(engine, failedDownloadWithError: e, forURL: u)
        default:
            // Only error/state events should be in edgeEvents; everything else
            // routes via the coalesced fields above.
            break
        }
    }
}
