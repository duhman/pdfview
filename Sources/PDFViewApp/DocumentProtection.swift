import Observation
@preconcurrency import Quartz

/// One instance per open PDF. Passwords exist only for this document session.
@MainActor
@Observable
final class DocumentProtection {
    let document: PDFDocument
    private(set) var knownPassword: String?
    private(set) var isLocked: Bool
    var keepPasswordProtection = true

    init(document: PDFDocument) {
        self.document = document
        isLocked = document.isLocked
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
    func refresh() {
        isLocked = document.isLocked
    }
}
