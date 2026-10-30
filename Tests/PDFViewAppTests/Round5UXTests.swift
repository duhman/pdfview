import AppKit
@preconcurrency import Quartz
import Testing
@testable import PDFViewApp

// MARK: Push buttons

@Test func aPushButtonSaysItCannotBeUsedFromTheKeyboard() {
    #expect(FormFieldNavigation.unavailableMessage(name: "Submit", kind: .button)
        == "Submit is a button and can’t be pressed from the keyboard.")
    #expect(FormFieldNavigation.unavailableMessage(name: nil, kind: .button)
        == "This button can’t be pressed from the keyboard.")
    #expect(FormFieldNavigation.unavailableMessage(name: "Agree", kind: .checkbox) == "Agree can’t be changed.")
}

// MARK: Saved banner path

@Test func theSavedMessageNamesTheFolderAsAnAbbreviatedPath() {
    let home = URL(fileURLWithPath: "/Users/a", isDirectory: true)
    let url = URL(fileURLWithPath: "/Users/a/Documents/Contracts/lease-signed.pdf")
    #expect(SigningFlowLogic.savedText(for: url, home: home) == "Saved “lease-signed.pdf” to ~/Documents/Contracts")
    #expect(SigningFlowLogic.savedAnnouncement(for: url, home: home)
        == "Saved lease-signed.pdf to ~/Documents/Contracts")
}

@Test func savedFolderNamesCoverHomeICloudDriveAndOtherVolumes() {
    let home = URL(fileURLWithPath: "/Users/a", isDirectory: true)
    func folder(_ path: String) -> String {
        SigningFlowLogic.folderDisplayName(of: URL(fileURLWithPath: path), home: home)
    }
    #expect(folder("/Users/a/lease.pdf") == "~")
    #expect(folder("/Users/a/Library/Mobile Documents/com~apple~CloudDocs/Leases/lease.pdf") == "iCloud Drive/Leases")
    #expect(folder("/Users/a/Library/Mobile Documents/com~apple~CloudDocs/lease.pdf") == "iCloud Drive")
    #expect(folder("/Volumes/USB/Signed/lease.pdf") == "/Volumes/USB/Signed")
    // A sibling whose name starts with the home folder's name is not inside it.
    #expect(folder("/Users/ab/lease.pdf") == "/Users/ab")
}

@Test func theRealHomeFolderIsUsedNotTheSandboxContainer() {
    #expect(!SigningFlowLogic.userHome.path.contains("/Library/Containers/"))
}

// MARK: Unlock

@Test func aSuccessfulUnlockIsAnnouncedWithThePageCount() {
    #expect(UnlockDocumentSheet.unlockedAnnouncement(pageCount: 1) == "Unlocked, 1 page")
    #expect(UnlockDocumentSheet.unlockedAnnouncement(pageCount: 12) == "Unlocked, 12 pages")
}
