import Foundation
@preconcurrency import Quartz

/// Go > Next/Previous Form Field: reading order through a document's editable widgets and the
/// words VoiceOver hears for each one.
enum FormFieldNavigation {
    enum Kind: Equatable {
        case text, checkbox, radioButton, button, popUp, list

        var spokenName: String {
            switch self {
            case .text: "text field"
            case .checkbox: "checkbox"
            case .radioButton: "radio button"
            case .button: "button"
            case .popUp: "pop-up menu"
            case .list: "list"
            }
        }
    }

    /// One widget, reduced to what ordering and announcing need.
    struct Field: Equatable {
        let pageIndex: Int
        let bounds: CGRect
        let name: String?
        let kind: Kind
    }

    static func kind(of widget: PDFAnnotation) -> Kind {
        switch widget.widgetFieldType {
        case .text: .text
        case .choice: widget.isListChoice ? .list : .popUp
        default:
            switch widget.widgetControlType {
            case .checkBoxControl: .checkbox
            case .radioButtonControl: .radioButton
            default: .button
            }
        }
    }

    /// The tooltip name (`/TU`) is written for people; the field name (`/T`) is the fallback.
    static func name(of widget: PDFAnnotation) -> String? {
        let userName = widget.value(forAnnotationKey: PDFAnnotationKey(rawValue: "/TU")) as? String
        return StampAccessibility.fieldDisplayName(userName) ?? StampAccessibility.fieldDisplayName(widget.fieldName)
    }

    /// Indices of `fields` in reading order: page, then top to bottom, then left to right.
    static func readingOrder(_ fields: [Field]) -> [Int] {
        func key(_ field: Field) -> (Int, CGFloat, CGFloat) {
            (field.pageIndex, -field.bounds.maxY, field.bounds.minX)
        }
        return fields.indices.sorted { key(fields[$0]) < key(fields[$1]) }
    }

    /// The position after (or before) `current` in a list of `count`, wrapping; the first or last
    /// field when nothing has been visited yet.
    static func adjacentPosition(after current: Int?, count: Int, forward: Bool) -> Int? {
        guard count > 0 else { return nil }
        guard let current else { return forward ? 0 : count - 1 }
        return (current + (forward ? 1 : -1) + count) % count
    }

    static func announcement(for field: Field) -> String {
        "\(field.name ?? "Unnamed field"), \(field.kind.spokenName), page \(field.pageIndex + 1)"
    }

    static let noFieldsAnnouncement = "This document has no form fields."
}
