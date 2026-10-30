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
