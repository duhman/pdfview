import SwiftUI

/// Help > Keyboard Shortcuts is generated from these rows, so it cannot drift from the menus.
extension MenuShortcuts {
    struct Entry {
        let menu: String
        let title: String
        let shortcut: KeyboardShortcut
    }

    /// Keys the document handles itself rather than through a menu.
    struct DocumentKey {
        let keys: String
        let action: String
    }

    /// Every menu chord, in menu-bar order. Titles that change with the stamp kind use their general form.
    static let entries: [Entry] = [
        Entry(menu: "File", title: "Save Signed Copy…", shortcut: saveSignedCopy),
        Entry(menu: "File", title: "Share Signed Copy…", shortcut: shareSignedCopy),
        Entry(menu: "File", title: "Show Signed Copy in Finder", shortcut: showSignedCopyInFinder),
        Entry(menu: "File", title: "Page Setup…", shortcut: pageSetup),
        Entry(menu: "File", title: "Print…", shortcut: print),
        Entry(menu: "Edit", title: "Find…", shortcut: find),
        Entry(menu: "Edit", title: "Find Next", shortcut: findNext),
        Entry(menu: "Edit", title: "Find Previous", shortcut: findPrevious),
        Entry(menu: "View", title: "Show/Hide Sidebar", shortcut: toggleSidebar),
        Entry(menu: "View", title: "Actual Size", shortcut: actualSize),
        Entry(menu: "View", title: "Zoom to Fit", shortcut: zoomToFit),
        Entry(menu: "View", title: "Zoom In", shortcut: zoomIn),
        Entry(menu: "View", title: "Zoom Out", shortcut: zoomOut),
        Entry(menu: "Go", title: "Next Page", shortcut: nextPage),
        Entry(menu: "Go", title: "Previous Page", shortcut: previousPage),
        Entry(menu: "Go", title: "First Page", shortcut: firstPage),
        Entry(menu: "Go", title: "Last Page", shortcut: lastPage),
        Entry(menu: "Go", title: "Next Form Field", shortcut: nextFormField),
        Entry(menu: "Go", title: "Previous Form Field", shortcut: previousFormField),
        Entry(menu: "Go", title: "Activate Form Field", shortcut: activateFormField),
        Entry(menu: "Go", title: "Go to Page…", shortcut: goToPage),
        Entry(menu: "Sign", title: "Start/Stop Signing", shortcut: toggleSigning),
        Entry(menu: "Sign", title: "Place Signature", shortcut: placeSignature),
        Entry(menu: "Sign", title: "Place Initials", shortcut: placeInitials),
        Entry(menu: "Sign", title: "Place Date", shortcut: placeDate),
        Entry(menu: "Sign", title: "Place Signature in Next Field", shortcut: placeInNextField),
        Entry(menu: "Sign", title: "Place on Current Page", shortcut: placeOnCurrentPage),
        Entry(menu: "Sign", title: "Place Initials on Every Page", shortcut: placeInitialsOnEveryPage),
        Entry(menu: "Sign", title: SignMenuTitles.selectNextStamp, shortcut: selectNextStamp),
        Entry(menu: "Sign", title: SignMenuTitles.selectPreviousStamp, shortcut: selectPreviousStamp),
    ]

    static let documentKeys: [DocumentKey] = [
        DocumentKey(keys: "← → ↑ ↓", action: "Move the selected stamp 1 pt (⇧ 10 pt, ⌘ 50 pt)"),
        DocumentKey(keys: "⌥⇧→ / ⌥⇧↑, ⌥⇧← / ⌥⇧↓", action: "Resize the selected stamp larger / smaller"),
        DocumentKey(keys: "⌫", action: "Remove the selected stamp from the page"),
        DocumentKey(keys: "Space / Return", action: "Activate the form field you just moved to"),
        DocumentKey(
            keys: "Esc",
            action: "Cancel a save, finish signing, close Find, deselect a stamp, or close the saved banner"
        ),
    ]

    /// "⌥⌘N": modifier glyphs in the order macOS menus show them (⌃⌥⇧⌘), then the key.
    static func display(_ shortcut: KeyboardShortcut) -> String {
        let glyphs: [(EventModifiers, String)] = [(.control, "⌃"), (.option, "⌥"), (.shift, "⇧"), (.command, "⌘")]
        let modifiers = glyphs.filter { shortcut.modifiers.contains($0.0) }.map(\.1).joined()
        return modifiers + keyName(shortcut.key, spoken: false)
    }

    /// "Option-Command-N", for VoiceOver, which reads the glyphs inconsistently.
    static func spoken(_ shortcut: KeyboardShortcut) -> String {
        let names: [(EventModifiers, String)] = [
            (.control, "Control"), (.option, "Option"), (.shift, "Shift"), (.command, "Command"),
        ]
        let modifiers = names.filter { shortcut.modifiers.contains($0.0) }.map(\.1)
        return (modifiers + [keyName(shortcut.key, spoken: true)]).joined(separator: "-")
    }

    private static func keyName(_ key: KeyEquivalent, spoken: Bool) -> String {
        let named: [(KeyEquivalent, String, String)] = [
            (.upArrow, "↑", "Up Arrow"), (.downArrow, "↓", "Down Arrow"),
            (.leftArrow, "←", "Left Arrow"), (.rightArrow, "→", "Right Arrow"),
            (.return, "↩", "Return"), (.space, "Space", "Space"), (.escape, "⎋", "Escape"),
            (.delete, "⌫", "Delete"),
        ]
        if let match = named.first(where: { $0.0.character == key.character }) {
            return spoken ? match.2 : match.1
        }
        return String(key.character).uppercased()
    }
}
