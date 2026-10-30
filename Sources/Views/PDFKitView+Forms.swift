import AppKit
@preconcurrency import Quartz

/// Keyboard activation of the form field Next/Previous Form Field moved to: checkboxes and radio
/// buttons toggle, pop-ups and lists open a menu of their choices, text fields start editing.
extension PDFKitView.Coordinator {
    /// The scanned widget Next/Previous Form Field last moved to.
    private var currentFormField: (widget: PDFAnnotation, page: PDFPage, pageIndex: Int)? {
        guard let document = pdfView?.document, let widgets = formScan?.widgets,
              let widget = widgets.first(where: { ObjectIdentifier($0) == lastFormFieldID }),
              let page = widget.page else { return nil }
        let index = document.index(for: page)
        return index == NSNotFound ? nil : (widget, page, index)
    }

    /// Changes the current field, or says why it cannot. Nil when nothing needs saying (a choice
    /// menu closed without a choice).
    func activateFormField() -> FormFieldActivation? {
        guard let (widget, page, _) = currentFormField else {
            return .unavailable(FormFieldNavigation.noFieldChosenNotice)
        }
        let kind = FormFieldNavigation.kind(of: widget)
        let name = FormFieldNavigation.name(of: widget)
        pdfView?.go(to: widget.bounds.insetBy(dx: -40, dy: -40), on: page)
        switch FormFieldNavigation.activation(kind: kind, isReadOnly: widget.isReadOnly) {
        case .toggle:
            widget.buttonWidgetState = widget.buttonWidgetState == .onState ? .offState : .onState
        case .select:
            // Turning one radio button on turns the others in its group off.
            let group = (formScan?.widgets ?? []).filter {
                $0 !== widget && $0.fieldName == widget.fieldName && FormFieldNavigation.kind(of: $0) == .radioButton
            }
            for sibling in group {
                sibling.buttonWidgetState = .offState
            }
            widget.buttonWidgetState = .onState
        case .choose:
            return chooseValue(for: widget, on: page)
        case .edit:
            // Once it has scrolled into view, as Next Form Field does.
            DispatchQueue.main.async { [weak pdfView] in
                pdfView?.clickWidget(widget, on: page)
            }
            return .changed("Editing \(name ?? "text field")")
        case .unavailable:
            return .unavailable(FormFieldNavigation.unavailableMessage(name: name, kind: kind))
        }
        return didChange(widget, on: page)
    }

    /// Sets a pop-up or list field's value, as picking it from its menu does.
    func apply(choice: String, to widget: PDFAnnotation) -> FormFieldActivation? {
        widget.widgetStringValue = choice
        return widget.page.flatMap { didChange(widget, on: $0) }
    }

    /// Runs the activation and reports it: VoiceOver reads a change, the banner shows why not.
    func performFormFieldActivation() {
        switch activateFormField() {
        case let .changed(message)?:
            StampAccessibility.announce(message, in: pdfView?.window)
        case let .unavailable(message)?:
            parent.onNotice(message)
        case nil:
            break
        }
    }

    /// Space or Return activates the field just moved to; any other key gives them back to PDFKit.
    func handleFormFieldKey(_ event: NSEvent) -> Bool {
        let isActivationKey = [49, 36, 76].contains(event.keyCode)
            && event.modifierFlags.isDisjoint(with: [.command, .option, .control, .shift])
        guard isActivationKey, acceptsFormFieldKeys, !stampOwnsArrowKeys else {
            acceptsFormFieldKeys = false
            return false
        }
        performFormFieldActivation()
        return true
    }

    private func didChange(_ widget: PDFAnnotation, on page: PDFPage) -> FormFieldActivation {
        pdfView?.annotationsChanged(on: page)
        checkFormValues()
        return .changed(FormFieldNavigation.changeAnnouncement(
            name: FormFieldNavigation.name(of: widget),
            kind: FormFieldNavigation.kind(of: widget),
            state: FormFieldNavigation.spokenState(of: widget)
        ))
    }

    /// PDFKit has no API to open a choice widget, so its choices are offered in a native menu at the field.
    private func chooseValue(for widget: PDFAnnotation, on page: PDFPage) -> FormFieldActivation? {
        let choices = widget.choices ?? []
        guard let pdfView, !choices.isEmpty else {
            return .unavailable("\(FormFieldNavigation.name(of: widget) ?? "This field") has no choices.")
        }
        let picker = ChoicePicker()
        let menu = NSMenu()
        for choice in choices {
            let item = NSMenuItem(title: choice, action: #selector(ChoicePicker.pick(_:)), keyEquivalent: "")
            item.target = picker
            item.state = choice == widget.widgetStringValue ? .on : .off
            menu.addItem(item)
        }
        let origin = pdfView.convert(CGPoint(x: widget.bounds.minX, y: widget.bounds.minY), from: page)
        menu.popUp(positioning: menu.items.first { $0.state == .on }, at: origin, in: pdfView)
        return picker.choice.flatMap { apply(choice: $0, to: widget) }
    }
}

/// Receives the menu item a choice menu's user picked.
@MainActor
private final class ChoicePicker: NSObject {
    private(set) var choice: String?

    @objc
    func pick(_ sender: NSMenuItem) {
        choice = sender.title
    }
}
