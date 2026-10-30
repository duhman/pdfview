import SwiftUI
import Testing
@testable import PDFViewApp

@Test func shortcutsAreWrittenWithTheMenuGlyphsInMacOSOrder() {
    #expect(MenuShortcuts.display(MenuShortcuts.placeInNextField) == "⌥⌘N")
    #expect(MenuShortcuts.display(MenuShortcuts.placeSignature) == "⌃⇧⌘S")
    #expect(MenuShortcuts.display(MenuShortcuts.placeInitials) == "⌥⇧⌘I")
    #expect(MenuShortcuts.display(MenuShortcuts.firstPage) == "⌥⌘↑")
    #expect(MenuShortcuts.display(MenuShortcuts.nextPage) == "⌥↓")
    #expect(MenuShortcuts.display(MenuShortcuts.nextFormField) == "⌥⌘→")
    #expect(MenuShortcuts.display(MenuShortcuts.activateFormField) == "⌥⌘↩")
    #expect(MenuShortcuts.display(MenuShortcuts.selectNextStamp) == "⌥⌘]")
    #expect(MenuShortcuts.display(MenuShortcuts.zoomOut) == "⌘-")
}

@Test func spokenShortcutsSpellOutTheModifiers() {
    #expect(MenuShortcuts.spoken(MenuShortcuts.placeInNextField) == "Option-Command-N")
    #expect(MenuShortcuts.spoken(MenuShortcuts.placeSignature) == "Control-Shift-Command-S")
    #expect(MenuShortcuts.spoken(MenuShortcuts.firstPage) == "Option-Command-Up Arrow")
    #expect(MenuShortcuts.spoken(MenuShortcuts.activateFormField) == "Option-Command-Return")
}

@Test func theBannerShowsTheSameChordsAsTheMenus() {
    #expect(SigningShortcut.placeInNextField == MenuShortcuts.display(MenuShortcuts.placeInNextField))
    #expect(SigningShortcut.placeOnCurrentPage == MenuShortcuts.display(MenuShortcuts.placeOnCurrentPage))
    #expect(SigningShortcut.selectNextStamp == MenuShortcuts.display(MenuShortcuts.selectNextStamp))
    #expect(SigningShortcut.placeInitialsOnEveryPage
        == MenuShortcuts.display(MenuShortcuts.placeInitialsOnEveryPage))
}

@Test func theShortcutsWindowListsEveryMenuChordOnce() {
    let listed = MenuShortcuts.entries.map { MenuShortcuts.Chord($0.shortcut) }
    #expect(listed.count == MenuShortcuts.all.count)
    #expect(Set(listed) == Set(MenuShortcuts.all.map(MenuShortcuts.Chord.init)))
    #expect(MenuShortcuts.entries.allSatisfy { !$0.title.isEmpty })
    #expect(Set(MenuShortcuts.entries.map(\.menu)) == ["File", "Edit", "View", "Go", "Sign"])
}

@Test func theShortcutsWindowAlsoListsDocumentKeys() {
    let actions = MenuShortcuts.documentKeys.map(\.action).joined(separator: " ")
    #expect(actions.contains("Move the selected stamp"))
    #expect(actions.contains("Resize"))
    #expect(actions.contains("Activate"))
    #expect(MenuShortcuts.documentKeys.map(\.keys).contains("Esc"))
}
