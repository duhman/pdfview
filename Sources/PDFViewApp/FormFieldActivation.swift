import Foundation
@preconcurrency import Quartz

/// What activating a form field from the keyboard did: a change for VoiceOver to read, or why
/// nothing changed, for the banner.
enum FormFieldActivation: Equatable {
    case changed(String)
    case unavailable(String)
}

/// Go > Activate Form Field (and Space or Return on the field just moved to): what each kind of
/// widget does and the words VoiceOver hears for its state.
extension FormFieldNavigation {
    enum Action: Equatable {
        case toggle, select, choose, edit, unavailable
    }

    static func activation(kind: Kind, isReadOnly: Bool) -> Action {
        guard !isReadOnly else { return .unavailable }
        return switch kind {
        case .checkbox: .toggle
        case .radioButton: .select
        case .popUp, .list: .choose
        case .text: .edit
        // A push button can run the PDF's own actions, so it is left to a deliberate click.
        case .button: .unavailable
        }
    }

    /// "checked", "not selected", a pop-up's value; nil where VoiceOver reads the field itself.
    static func spokenState(kind: Kind, isOn: Bool, value: String?) -> String? {
        switch kind {
        case .checkbox: isOn ? "checked" : "unchecked"
        case .radioButton: isOn ? "selected" : "not selected"
        case .popUp, .list: StampAccessibility.fieldDisplayName(value) ?? "no selection"
        case .text, .button: nil
        }
    }

    static func spokenState(of widget: PDFAnnotation) -> String? {
        spokenState(
            kind: kind(of: widget),
            isOn: widget.buttonWidgetState == .onState,
            value: widget.widgetStringValue
        )
    }

    /// "Agree, checkbox, checked, page 2".
    static func announcement(for field: Field, state: String?) -> String {
        [field.name ?? "Unnamed field", field.kind.spokenName, state, "page \(field.pageIndex + 1)"]
            .compactMap(\.self)
            .joined(separator: ", ")
    }

    /// "Agree, checkbox, checked": the new state, without the page the user is already on.
    static func changeAnnouncement(name: String?, kind: Kind, state: String?) -> String {
        [name ?? "Unnamed field", kind.spokenName, state].compactMap(\.self).joined(separator: ", ")
    }

    static func unavailableMessage(name: String?, kind: Kind) -> String {
        kind == .button
            ? "\(name ?? "This button") is a button. Click it to use it."
            : "\(name ?? "This field") can’t be changed."
    }

    static let noFieldChosenNotice = "Choose Go > Next Form Field first, then activate the field."
}
