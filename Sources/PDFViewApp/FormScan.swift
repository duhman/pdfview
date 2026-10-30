@preconcurrency import Quartz

/// One form widget's user-editable value, compared to tell whether the user changed the form.
struct FormFieldValue: Equatable {
    let fieldName: String?
    let stringValue: String?
    let buttonState: Int
}

/// Signature fields and editable widgets found by walking the document a few pages at a time,
/// so a long PDF shows its pages before every page's annotations have been read.
@MainActor
struct FormScan {
    var signatureFields: [SignatureField] = []
    /// Every non-signature widget, in page order; their values are the form's unsaved work.
    var widgets: [PDFAnnotation] = []
    var isCancelled = false

    static func scan(_ document: PDFDocument, pagesPerYield: Int = 8) async -> FormScan {
        var result = FormScan()
        for pageIndex in 0 ..< document.pageCount {
            if pageIndex.isMultiple(of: max(pagesPerYield, 1)) {
                if pageIndex > 0 {
                    await Task.yield()
                }
                if Task.isCancelled {
                    result.isCancelled = true
                    return result
                }
            }
            guard let page = document.page(at: pageIndex) else { continue }
            for annotation in page.annotations where annotation.type == "Widget" {
                if SigningFlowLogic.isSignatureField(annotation) {
                    result.signatureFields.append(SignatureField(
                        pageIndex: pageIndex,
                        bounds: annotation.bounds,
                        name: annotation.fieldName
                    ))
                } else {
                    result.widgets.append(annotation)
                }
            }
        }
        return result
    }

    func values() -> [FormFieldValue] {
        widgets.map {
            FormFieldValue(
                fieldName: $0.fieldName,
                stringValue: $0.widgetStringValue,
                buttonState: $0.buttonWidgetState.rawValue
            )
        }
    }
}
