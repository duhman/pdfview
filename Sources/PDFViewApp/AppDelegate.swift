import AppKit

/// Asks about unsaved signatures and form entries before the app quits.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        let windows = sender.orderedWindows.compactMap(DocumentCloseGuard.installed(on:))
        guard windows.contains(where: \.hasUnsavedWork) else { return .terminateNow }
        // Reply on a later turn: AppKit expects the answer after this method has returned.
        DispatchQueue.main.async {
            TerminationReview.run(windows, choose: TerminationReview.askToReview(count:)) { proceed in
                sender.reply(toApplicationShouldTerminate: proceed)
            }
        }
        return .terminateLater
    }
}
