import AppKit

/// A document window that may hold unsaved signatures or form entries when the app quits.
@MainActor
protocol QuitReviewable: AnyObject {
    var hasUnsavedWork: Bool { get }
    /// Shows the window's save prompt and reports true to keep quitting, false to cancel the quit.
    func reviewBeforeQuitting(then done: @escaping (Bool) -> Void)
}

enum QuitReviewChoice {
    case review
    case discardAll
    case cancel
}

/// The quit decision NSDocumentController makes for edited documents, applied to signing windows,
/// which SwiftUI's viewer documents never mark as edited.
@MainActor
enum TerminationReview {
    nonisolated static let summaryInformation = "If you don’t review your documents, all your changes will be lost."

    nonisolated static func summaryMessage(count: Int) -> String {
        "You have \(count) documents with unsaved signatures or form entries. "
            + "Do you want to review them before quitting?"
    }

    /// One unsaved window goes straight to its own prompt; several ask first whether to review them.
    static func run(
        _ windows: [QuitReviewable],
        choose: (_ count: Int) -> QuitReviewChoice,
        completion: @escaping (Bool) -> Void
    ) {
        let pending = windows.filter(\.hasUnsavedWork)
        guard !pending.isEmpty else {
            completion(true)
            return
        }
        switch pending.count == 1 ? .review : choose(pending.count) {
        case .review: review(pending[...], completion: completion)
        case .discardAll: completion(true)
        case .cancel: completion(false)
        }
    }

    private static func review(_ windows: ArraySlice<QuitReviewable>, completion: @escaping (Bool) -> Void) {
        guard let window = windows.first else {
            completion(true)
            return
        }
        window.reviewBeforeQuitting { proceed in
            if proceed {
                review(windows.dropFirst(), completion: completion)
            } else {
                completion(false)
            }
        }
    }

    /// The modal summary alert shown when more than one window has unsaved work.
    static func askToReview(count: Int) -> QuitReviewChoice {
        let alert = NSAlert()
        alert.messageText = summaryMessage(count: count)
        alert.informativeText = summaryInformation
        alert.addButton(withTitle: "Review Changes…")
        alert.addButton(withTitle: "Cancel")
        let discard = alert.addButton(withTitle: "Discard Changes")
        discard.hasDestructiveAction = true
        switch alert.runModal() {
        case .alertFirstButtonReturn: return .review
        case .alertThirdButtonReturn: return .discardAll
        default: return .cancel
        }
    }
}
