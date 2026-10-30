import AppKit
@preconcurrency import Quartz
import Testing
@testable import PDFViewApp

@MainActor
private func widget(
    _ type: PDFAnnotationWidgetSubtype,
    name: String,
    at rect: CGRect,
    control: PDFWidgetControlType = .unknownControl
) -> PDFAnnotation {
    let widget = PDFAnnotation(bounds: rect, forType: .widget, withProperties: nil)
    widget.widgetFieldType = type
    widget.fieldName = name
    if control != .unknownControl {
        widget.widgetControlType = control
    }
    return widget
}

/// A page with, top to bottom: an "Agree" checkbox, a "Department" pop-up and a read-only checkbox.
@MainActor
private func makeChoicesForm() throws -> PDFDocument {
    let document = try ExportFixture.document()
    let page = try #require(document.page(at: 0))
    let agreeBounds = CGRect(x: 40, y: 500, width: 20, height: 20)
    page.addAnnotation(widget(.button, name: "Agree", at: agreeBounds, control: .checkBoxControl))
    let popUp = widget(.choice, name: "Department", at: CGRect(x: 40, y: 400, width: 160, height: 24))
    popUp.isListChoice = false
    popUp.choices = ["Sales", "Legal"]
    popUp.widgetStringValue = "Sales"
    page.addAnnotation(popUp)
    let lockedBounds = CGRect(x: 40, y: 300, width: 20, height: 20)
    let locked = widget(.button, name: "Locked", at: lockedBounds, control: .checkBoxControl)
    locked.isReadOnly = true
    page.addAnnotation(locked)
    return document
}

/// The coordinator holds its PDF view weakly, so the caller keeps `pdfView` alive.
@MainActor
private func scannedCoordinator(
    for document: PDFDocument,
    recorder: StateRecorder
) async throws -> (coordinator: PDFKitView.Coordinator, pdfView: SigningPDFView) {
    let coordinator = makeRepresentable(document: document, recorder: recorder).makeCoordinator()
    let pdfView = SigningPDFView(frame: CGRect(x: 0, y: 0, width: 400, height: 600))
    coordinator.attach(to: pdfView)
    pdfView.document = document
    coordinator.documentDidChange(document)
    for _ in 0 ..< 200 where recorder.states.last?.formValues == nil {
        await Task.yield()
    }
    try #require(recorder.states.last?.formValues != nil)
    return (coordinator, pdfView)
}

// MARK: Announcements

@Test func fieldAnnouncementsIncludeTheFieldsState() {
    let agree = FormFieldNavigation.Field(pageIndex: 1, bounds: .zero, name: "Agree", kind: .checkbox)
    #expect(FormFieldNavigation.announcement(for: agree, state: "checked") == "Agree, checkbox, checked, page 2")
    #expect(FormFieldNavigation.announcement(for: agree, state: nil) == "Agree, checkbox, page 2")
}

@Test func spokenStateDependsOnTheKind() {
    #expect(FormFieldNavigation.spokenState(kind: .checkbox, isOn: true, value: nil) == "checked")
    #expect(FormFieldNavigation.spokenState(kind: .checkbox, isOn: false, value: nil) == "unchecked")
    #expect(FormFieldNavigation.spokenState(kind: .radioButton, isOn: true, value: nil) == "selected")
    #expect(FormFieldNavigation.spokenState(kind: .radioButton, isOn: false, value: nil) == "not selected")
    #expect(FormFieldNavigation.spokenState(kind: .popUp, isOn: false, value: "Sales") == "Sales")
    #expect(FormFieldNavigation.spokenState(kind: .list, isOn: false, value: "") == "no selection")
    // Text fields are read by VoiceOver once they are being edited; buttons have no state.
    #expect(FormFieldNavigation.spokenState(kind: .text, isOn: false, value: "Ada") == nil)
    #expect(FormFieldNavigation.spokenState(kind: .button, isOn: false, value: nil) == nil)
}

@Test func activationTogglesChoosesOrEditsByKind() {
    #expect(FormFieldNavigation.activation(kind: .checkbox, isReadOnly: false) == .toggle)
    #expect(FormFieldNavigation.activation(kind: .radioButton, isReadOnly: false) == .select)
    #expect(FormFieldNavigation.activation(kind: .popUp, isReadOnly: false) == .choose)
    #expect(FormFieldNavigation.activation(kind: .list, isReadOnly: false) == .choose)
    #expect(FormFieldNavigation.activation(kind: .text, isReadOnly: false) == .edit)
    #expect(FormFieldNavigation.activation(kind: .checkbox, isReadOnly: true) == .unavailable)
    #expect(FormFieldNavigation.activation(kind: .button, isReadOnly: false) == .unavailable)
}

// MARK: Activating from the keyboard

@MainActor
@Test func activateFieldTogglesTheCheckboxAndReportsTheChange() async throws {
    let document = try makeChoicesForm()
    let recorder = StateRecorder()
    let (coordinator, pdfView) = try await scannedCoordinator(for: document, recorder: recorder)
    defer { withExtendedLifetime(pdfView) {} }
    #expect(coordinator.activateFormField() == .unavailable(FormFieldNavigation.noFieldChosenNotice))

    #expect(coordinator.moveToFormField(forward: true) == "Agree, checkbox, unchecked, page 1")
    #expect(coordinator.activateFormField() == .changed("Agree, checkbox, checked"))
    let agree = try #require(document.page(at: 0)?.annotations.first { $0.fieldName == "Agree" })
    #expect(agree.buttonWidgetState == .onState)
    // The edit counts as unsaved form work straight away.
    #expect(recorder.formValues.last?.contains { $0.fieldName == "Agree" && $0.buttonState == 1 } == true)
    #expect(coordinator.activateFormField() == .changed("Agree, checkbox, unchecked"))
}

@MainActor
@Test func navigationAnnouncesAPopUpsValueAndAChoiceCanBeApplied() async throws {
    let document = try makeChoicesForm()
    let recorder = StateRecorder()
    let (coordinator, pdfView) = try await scannedCoordinator(for: document, recorder: recorder)
    defer { withExtendedLifetime(pdfView) {} }
    _ = coordinator.moveToFormField(forward: true)
    #expect(coordinator.moveToFormField(forward: true) == "Department, pop-up menu, Sales, page 1")
    let department = try #require(document.page(at: 0)?.annotations.first { $0.fieldName == "Department" })
    #expect(coordinator.apply(choice: "Legal", to: department) == .changed("Department, pop-up menu, Legal"))
    #expect(department.widgetStringValue == "Legal")
    #expect(recorder.formValues.last?.contains { $0.fieldName == "Department" && $0.stringValue == "Legal" } == true)
}

@MainActor
@Test func nextFormFieldSkipsAReadOnlyField() async throws {
    let document = try makeChoicesForm()
    let (coordinator, pdfView) = try await scannedCoordinator(for: document, recorder: StateRecorder())
    defer { withExtendedLifetime(pdfView) {} }
    // "Locked" is last in reading order but read-only, so Previous Form Field lands on Department.
    #expect(coordinator.moveToFormField(forward: false) == "Department, pop-up menu, Sales, page 1")
    #expect(FormFieldNavigation.unavailableMessage(name: "Locked", kind: .checkbox) == "Locked can’t be changed.")
}

@MainActor
@Test func spaceActivatesTheFieldJustMovedToAndOtherKeysGiveSpaceBackToScrolling() async throws {
    let document = try makeChoicesForm()
    let (coordinator, pdfView) = try await scannedCoordinator(for: document, recorder: StateRecorder())
    defer { withExtendedLifetime(pdfView) {} }
    let agree = try #require(document.page(at: 0)?.annotations.first { $0.fieldName == "Agree" })
    let space = try keyEvent(0x20, keyCode: 49, function: false)

    // Before any field navigation, Space scrolls as usual.
    #expect(!coordinator.handleKey(space))
    _ = coordinator.moveToFormField(forward: true)
    #expect(coordinator.handleKey(space))
    #expect(agree.buttonWidgetState == .onState)

    // Any other key, a click or a scroll ends keyboard activation of that field.
    _ = try coordinator.handleKey(keyEvent(NSDownArrowFunctionKey, keyCode: 125))
    #expect(!coordinator.handleKey(space))
    #expect(agree.buttonWidgetState == .onState)
}

@Test func activateFormFieldHasItsOwnShortcut() {
    let chords = MenuShortcuts.appSpecific.map(MenuShortcuts.Chord.init)
    #expect(chords.contains(MenuShortcuts.Chord(MenuShortcuts.activateFormField)))
}
