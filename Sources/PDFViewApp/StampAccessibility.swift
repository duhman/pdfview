import AppKit

/// Words VoiceOver uses for a placed stamp: who signed, which page, and which field or part of the page.
enum StampAccessibility {
    /// Thirds of the page as it appears on screen, so "top right" matches what a sighted helper sees.
    static func position(of bounds: CGRect, in cropBox: CGRect, rotation: Int = 0) -> String {
        guard cropBox.width > 0, cropBox.height > 0 else { return "center" }
        let u = (bounds.midX - cropBox.minX) / cropBox.width
        let v = (bounds.midY - cropBox.minY) / cropBox.height
        // PDF rotation turns the page clockwise for display.
        let (x, y) = switch ((rotation % 360) + 360) % 360 {
        case 90: (v, 1 - u)
        case 180: (1 - u, 1 - v)
        case 270: (1 - v, u)
        default: (u, v)
        }
        let row = y > 2.0 / 3 ? "top" : (y < 1.0 / 3 ? "bottom" : "middle")
        let column = x < 1.0 / 3 ? "left" : (x > 2.0 / 3 ? "right" : "center")
        switch (row, column) {
        case ("middle", "center"): return "center"
        case ("middle", _): return "middle \(column)"
        default: return "\(row) \(column)"
        }
    }

    /// Field names come from the PDF: control characters and runs of whitespace are flattened and the
    /// name is cut to 40 characters, so a crafted name cannot add lines or long text to announcements.
    static func fieldDisplayName(_ name: String?, limit: Int = 40) -> String? {
        guard let name else { return nil }
        let words = name.unicodeScalars
            .map {
                CharacterSet.controlCharacters.contains($0) || CharacterSet.whitespacesAndNewlines
                    .contains($0) ? " " : Character($0)
            }
            .split(separator: " ")
            .map { String($0) }
        let flat = words.joined(separator: " ")
        guard !flat.isEmpty else { return nil }
        return flat.count > limit ? String(flat.prefix(limit)) + "…" : flat
    }

    /// "in field “Buyer”" when the stamp sits in a detected signature field, otherwise "at top right".
    static func location(
        of bounds: CGRect,
        pageIndex: Int,
        cropBox: CGRect,
        rotation: Int = 0,
        fields: [SignatureField]
    ) -> String {
        let center = CGPoint(x: bounds.midX, y: bounds.midY)
        if let field = fields.first(where: { $0.pageIndex == pageIndex && $0.bounds.contains(center) }) {
            if let name = fieldDisplayName(field.name) {
                return "in field “\(name)”"
            }
            return "in a signature field"
        }
        return "at \(position(of: bounds, in: cropBox, rotation: rotation))"
    }

    static func label(
        signerName: String,
        pageIndex: Int,
        bounds: CGRect,
        cropBox: CGRect,
        rotation: Int = 0,
        fields: [SignatureField],
        kind: StampKind = .signature,
        dateText: String? = nil
    ) -> String {
        let place = location(of: bounds, pageIndex: pageIndex, cropBox: cropBox, rotation: rotation, fields: fields)
        let subject = kind == .date ? "Date \(dateText ?? "")" : "\(kind.title) by \(signerName)"
        return "\(subject), page \(pageIndex + 1), \(place)"
    }

    /// The new stamp is selected, so the announcement says how to adjust it and how to finish.
    static func placedAnnouncement(pageIndex: Int, location: String, kind: StampKind = .signature) -> String {
        "\(kind.title) placed on page \(pageIndex + 1), \(location). Arrow keys move it, Escape when done."
    }

    static func movedAnnouncement(pageIndex: Int, location: String) -> String {
        "Moved, page \(pageIndex + 1), \(location)"
    }

    static func moveInstructions(for kind: StampKind) -> String {
        "Use the arrow keys to move the \(kind.title.lowercased()): Shift moves 10 points. "
            + "Option-Shift arrows resize it. Delete removes it. Escape when done."
    }

    @MainActor
    static func announce(_ message: String, in window: NSWindow?, priority: NSAccessibilityPriorityLevel = .high) {
        NSAccessibility.post(
            element: window ?? NSApp as Any,
            notification: .announcementRequested,
            userInfo: [.announcement: message, .priority: priority.rawValue]
        )
    }
}

/// One placed stamp as VoiceOver sees it: a button that selects the stamp, with Remove and Move actions.
/// AppKit calls accessibility methods on the main thread, which is what `assumeIsolated` relies on.
@MainActor
final class StampAccessibilityElement: NSAccessibilityElement {
    let stampID: UUID
    // swiftlint:disable:next modifier_order
    private nonisolated(unsafe) weak var overlay: PageOverlayView?

    init(stampID: UUID, kind: StampKind = .signature, overlay: PageOverlayView) {
        self.stampID = stampID
        self.overlay = overlay
        super.init()
        setAccessibilityRole(.button)
        setAccessibilityParent(overlay)
        setAccessibilityCustomActions([
            NSAccessibilityCustomAction(name: kind.actionName(.remove)) { [weak self] in
                self?.perform { $0.removeStampFromAccessibility($1) } ?? false
            },
            NSAccessibilityCustomAction(name: "Move") { [weak self] in
                self?.perform { $0.moveStampFromAccessibility($1) } ?? false
            },
        ])
    }

    override nonisolated func accessibilityFrame() -> NSRect {
        let id = stampID
        let overlay = overlay
        return MainActor.assumeIsolated {
            overlay?.screenFrame(ofStamp: id) ?? .zero
        }
    }

    override nonisolated func accessibilityPerformPress() -> Bool {
        let id = stampID
        let overlay = overlay
        return MainActor.assumeIsolated {
            overlay?.selectStampFromAccessibility(id)
            return overlay != nil
        }
    }

    private func perform(_ action: (PageOverlayView, UUID) -> Void) -> Bool {
        guard let overlay else { return false }
        action(overlay, stampID)
        return true
    }
}
