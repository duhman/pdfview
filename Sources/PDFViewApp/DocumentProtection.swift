import Observation
@preconcurrency import Quartz

/// One instance per open PDF. Passwords exist only for this document session.
@MainActor
@Observable
final class DocumentProtection: NSObject {
    let document: PDFDocument
    private(set) var knownPassword: String?
    private(set) var isLocked: Bool
    private(set) var formBaseline: FormScan?
    private(set) var initialFormValues: [FormFieldValue]?
    var keepPasswordProtection = true

    init(document: PDFDocument, formBaseline: FormScan? = nil, initialFormValues: [FormFieldValue]? = nil) {
        self.document = document
        isLocked = document.isLocked
        let baseline = formBaseline ?? FormScan.capture(document)
        self.formBaseline = baseline
        self.initialFormValues = initialFormValues ?? baseline?.values()
        super.init()
        NotificationCenter.default.addObserver(
            self, selector: #selector(refresh), name: .PDFDocumentDidUnlock, object: document
        )
    }

    var isEncrypted: Bool {
        document.isEncrypted
    }

    var canKeepPasswordProtection: Bool {
        isEncrypted && knownPassword != nil
    }

    var exportPassword: String? {
        canKeepPasswordProtection && keepPasswordProtection ? knownPassword : nil
    }

    var exportNotice: String {
        guard isEncrypted else { return "" }
        guard knownPassword != nil else {
            return "The document's password is unknown. The signed copy will not be password protected."
        }
        return keepPasswordProtection ? "The signed copy will use the same password." :
            "The signed copy will not be password protected."
    }

    @discardableResult
    func unlock(withPassword password: String) -> Bool {
        guard document.isLocked else {
            refresh()
            return true
        }
        guard document.unlock(withPassword: password) else { return false }
        knownPassword = password
        refresh()
        return true
    }

    /// Call after PDFKit's native unlock path; that path cannot reveal its password.
    @objc func refresh() {
        isLocked = document.isLocked
        if formBaseline == nil, !isLocked {
            formBaseline = FormScan.capture(document)
            initialFormValues = formBaseline?.values()
        }
    }

    deinit { NotificationCenter.default.removeObserver(self) }
}

/// Retains the password only while this window shows the same PDFKit document.
@MainActor
@Observable
final class DocumentProtectionSession {
    private(set) var protection: DocumentProtection?
    var showsUnlock = false

    func attach(_ document: PDFDocument?, formBaseline: FormScan? = nil, initialFormValues: [FormFieldValue]? = nil) {
        guard protection?.document !== document else { return }
        protection = document.map {
            DocumentProtection(document: $0, formBaseline: formBaseline, initialFormValues: initialFormValues)
        }
        showsUnlock = protection?.isLocked == true
    }

    func refresh() {
        protection?.refresh()
        if protection?.isLocked != true {
            showsUnlock = false
        }
    }

    func requestUnlock() {
        refresh()
        showsUnlock = protection?.isLocked == true
    }
}
