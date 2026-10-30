import Foundation
import Observation

/// A short message the window shows in its banner for a few seconds instead of a bare beep, e.g.
/// "Every signature field already has a stamp." VoiceOver hears it through an announcement.
@MainActor
@Observable
final class TransientNotice {
    private(set) var text: String?
    private let duration: Duration
    /// Each message gets its own number, so an older message's timer cannot clear a newer one.
    private var generation = 0

    init(duration: Duration = .seconds(4)) {
        self.duration = duration
    }

    /// Long enough to read a two-sentence instruction, e.g. how to adjust a stamp just placed.
    static let instructionDuration: Duration = .seconds(8)

    /// Shows `text` for `duration`, or for the notice's default when nil.
    func show(_ text: String, for duration: Duration? = nil) {
        generation += 1
        let shown = generation
        self.text = text
        Task { [weak self, duration = duration ?? self.duration] in
            try? await Task.sleep(for: duration)
            guard let self, generation == shown else { return }
            self.text = nil
        }
    }

    func dismiss() {
        generation += 1
        text = nil
    }
}

/// Becomes visible only after `delay`, so a save or print that finishes quickly never flashes its
/// progress banner (or announces it).
@MainActor
@Observable
final class DelayedVisibility {
    static let progressDelay: Duration = .milliseconds(300)

    private(set) var isVisible = false
    private let delay: Duration
    private var task: Task<Void, Never>?

    init(delay: Duration = progressDelay) {
        self.delay = delay
    }

    /// Starts waiting; does nothing while already waiting or visible.
    func begin() {
        guard task == nil, !isVisible else { return }
        task = Task { [weak self, delay] in
            try? await Task.sleep(for: delay)
            guard let self, !Task.isCancelled else { return }
            isVisible = true
            task = nil
        }
    }

    func end() {
        task?.cancel()
        task = nil
        isVisible = false
    }
}
