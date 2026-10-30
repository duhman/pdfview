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

    func show(_ text: String) {
        generation += 1
        let shown = generation
        self.text = text
        Task { [weak self, duration] in
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
