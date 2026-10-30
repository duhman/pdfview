import AppKit
import Observation
import SwiftUI

/// What Edit > Undo and Redo say and whether they can act, for one undo manager.
struct UndoMenuState: Equatable {
    var undoTitle = "Undo"
    var redoTitle = "Redo"
    var canUndo = false
    var canRedo = false

    init() {}

    @MainActor
    init(_ undoManager: UndoManager?) {
        guard let undoManager else { return }
        undoTitle = undoManager.undoMenuItemTitle
        redoTitle = undoManager.redoMenuItemTitle
        canUndo = undoManager.canUndo
        canRedo = undoManager.canRedo
    }
}

/// Follows the key window's undo manager, so the Edit menu can name the step ("Undo Add Signature").
/// SwiftUI's own Undo item read plain "Undo" once the document stopped having an undo manager and
/// stamp edits moved to the window's (see `DocumentCloseGuard.install`).
@MainActor
@Observable
final class UndoMenuModel: NSObject {
    private(set) var state = UndoMenuState()

    override init() {
        super.init()
        let center = NotificationCenter.default
        let names: [Notification.Name] = [
            .NSUndoManagerDidCloseUndoGroup, .NSUndoManagerDidUndoChange, .NSUndoManagerDidRedoChange,
            .NSUndoManagerWillCloseUndoGroup, .NSUndoManagerDidOpenUndoGroup,
            NSWindow.didBecomeKeyNotification, NSWindow.didResignKeyNotification,
        ]
        for name in names {
            center.addObserver(self, selector: #selector(undoStateChanged), name: name, object: nil)
        }
    }

    /// The manager `undo:` reaches through the responder chain from the key window.
    static var keyUndoManager: UndoManager? {
        guard let window = NSApp.keyWindow else { return nil }
        return window.firstResponder?.undoManager ?? window.undoManager
    }

    /// Undo managers post on the thread that changed them, which is not always the main thread.
    @objc
    nonisolated func undoStateChanged() {
        if Thread.isMainThread {
            MainActor.assumeIsolated { refresh() }
        } else {
            DispatchQueue.main.async { [weak self] in self?.refresh() }
        }
    }

    func refresh() {
        let next = UndoMenuState(Self.keyUndoManager)
        if next != state {
            state = next
        }
    }
}

/// Replaces SwiftUI's Undo and Redo so their titles carry the action name. They send the standard
/// `undo:` and `redo:` actions, so text fields and the signature canvas keep their own undo.
struct UndoCommands: Commands {
    let model: UndoMenuModel

    var body: some Commands {
        CommandGroup(replacing: .undoRedo) {
            Button(model.state.undoTitle) {
                NSApp.sendAction(Selector(("undo:")), to: nil, from: nil)
                model.refresh()
            }
            .keyboardShortcut("z", modifiers: .command)
            .disabled(!model.state.canUndo)

            Button(model.state.redoTitle) {
                NSApp.sendAction(Selector(("redo:")), to: nil, from: nil)
                model.refresh()
            }
            .keyboardShortcut("z", modifiers: [.command, .shift])
            .disabled(!model.state.canRedo)
        }
    }
}
