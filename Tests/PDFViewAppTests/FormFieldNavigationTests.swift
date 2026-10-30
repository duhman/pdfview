import AppKit
@preconcurrency import Quartz
import Testing
@testable import PDFViewApp

private func widget(_ type: PDFAnnotationWidgetSubtype, bounds: CGRect, name: String) -> PDFAnnotation {
    let annotation = PDFAnnotation(bounds: bounds, forType: .widget, withProperties: nil)
    annotation.widgetFieldType = type
    annotation.fieldName = name
    return annotation
}

@Test func widgetKindsHaveSpokenNames() {
    let text = widget(.text, bounds: .zero, name: "Name")
    let check = widget(.button, bounds: .zero, name: "Agree")
    check.widgetControlType = .checkBoxControl
    let radio = widget(.button, bounds: .zero, name: "Plan")
    radio.widgetControlType = .radioButtonControl
    let choice = widget(.choice, bounds: .zero, name: "Country")
    choice.isListChoice = false
    let list = widget(.choice, bounds: .zero, name: "Colours")
    list.isListChoice = true
    #expect(FormFieldNavigation.kind(of: text) == .text)
    #expect(FormFieldNavigation.kind(of: check) == .checkbox)
    #expect(FormFieldNavigation.kind(of: radio) == .radioButton)
    #expect(FormFieldNavigation.kind(of: choice) == .popUp)
    #expect(FormFieldNavigation.kind(of: list) == .list)
    #expect(FormFieldNavigation.Kind.text.spokenName == "text field")
}

@Test func widgetNamePrefersTheTooltipAndIsCleaned() {
    let text = widget(.text, bounds: .zero, name: "txt_1")
    #expect(FormFieldNavigation.name(of: text) == "txt_1")
    text.setValue("Full\nname", forAnnotationKey: PDFAnnotationKey(rawValue: "/TU"))
    #expect(FormFieldNavigation.name(of: text) == "Full name")
}

@Test func fieldsAreVisitedInReadingOrderAndWrap() {
    let fields = [
        FormFieldNavigation.Field(
            pageIndex: 1,
            bounds: CGRect(x: 0, y: 500, width: 10, height: 10),
            name: "C",
            kind: .text
        ),
        FormFieldNavigation.Field(
            pageIndex: 0,
            bounds: CGRect(x: 0, y: 100, width: 10, height: 10),
            name: "B",
            kind: .text
        ),
        FormFieldNavigation.Field(
            pageIndex: 0,
            bounds: CGRect(x: 0, y: 700, width: 10, height: 10),
            name: "A",
            kind: .text
        ),
    ]
    #expect(FormFieldNavigation.readingOrder(fields).map { fields[$0].name } == ["A", "B", "C"])
    #expect(FormFieldNavigation.adjacentPosition(after: nil, count: 3, forward: true) == 0)
    #expect(FormFieldNavigation.adjacentPosition(after: nil, count: 3, forward: false) == 2)
    #expect(FormFieldNavigation.adjacentPosition(after: 2, count: 3, forward: true) == 0)
    #expect(FormFieldNavigation.adjacentPosition(after: 0, count: 3, forward: false) == 2)
    #expect(FormFieldNavigation.adjacentPosition(after: nil, count: 0, forward: true) == nil)
}

@Test func fieldAnnouncementNamesTheFieldItsKindAndPage() {
    let field = FormFieldNavigation.Field(pageIndex: 2, bounds: .zero, name: "Email", kind: .text)
    #expect(FormFieldNavigation.announcement(for: field) == "Email, text field, page 3")
    let unnamed = FormFieldNavigation.Field(pageIndex: 0, bounds: .zero, name: nil, kind: .checkbox)
    #expect(FormFieldNavigation.announcement(for: unnamed) == "Unnamed field, checkbox, page 1")
}

@MainActor
@Test func nextFormFieldMovesThroughTheScannedWidgets() async throws {
    let document = try makeSignableForm()
    let recorder = StateRecorder()
    let coordinator = makeRepresentable(document: document, recorder: recorder).makeCoordinator()
    let pdfView = SigningPDFView(frame: CGRect(x: 0, y: 0, width: 400, height: 600))
    coordinator.attach(to: pdfView)
    pdfView.document = document
    #expect(coordinator.moveToFormField(forward: true) == nil)

    coordinator.documentDidChange(document)
    for _ in 0 ..< 200 where recorder.states.last?.formValues == nil {
        await Task.yield()
    }
    // The signature widget is a stamp target, not a form field, so the text field is the only stop.
    #expect(coordinator.moveToFormField(forward: true) == "Name, text field, page 1")
    #expect(coordinator.moveToFormField(forward: true) == "Name, text field, page 1")
    #expect(coordinator.moveToFormField(forward: false) == "Name, text field, page 1")
}
