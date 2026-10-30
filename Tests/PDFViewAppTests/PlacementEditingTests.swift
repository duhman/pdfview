import Foundation
import SwiftUI
import Testing
@testable import PDFViewApp

@MainActor
private final class EditingFixture {
    var document = PDFViewerDocument()
    let undoManager = UndoManager()
    let editor = SignaturePlacementEditor()

    init() {
        undoManager.groupsByEvent = false
        editor.document = Binding(get: { self.document }, set: { self.document = $0 })
        editor.undoManager = undoManager
    }

    func step(_ action: () -> Void) {
        undoManager.beginUndoGrouping()
        action()
        undoManager.endUndoGrouping()
    }

    static func placement(x: CGFloat) -> PDFViewerDocument.SignaturePlacement {
        PDFViewerDocument.SignaturePlacement(
            pageIndex: 0,
            bounds: CGRect(x: x, y: 10, width: 180, height: 60),
            signaturePNGData: Data([1]),
            signerName: "Tester"
        )
    }
}

@MainActor
@Test func addUndoRedoRoundTrip() {
    let fixture = EditingFixture()
    let placement = EditingFixture.placement(x: 10)

    fixture.step { fixture.editor.add(placement) }
    #expect(fixture.document.signaturePlacements == [placement])
    #expect(fixture.undoManager.undoActionName == "Add Signature")

    fixture.undoManager.undo()
    #expect(fixture.document.signaturePlacements.isEmpty)

    fixture.undoManager.redo()
    #expect(fixture.document.signaturePlacements == [placement])
}

@MainActor
@Test func moveUndoRestoresPreviousBounds() {
    let fixture = EditingFixture()
    let placement = EditingFixture.placement(x: 10)
    let target = CGRect(x: 200, y: 300, width: 180, height: 60)

    fixture.step { fixture.editor.add(placement) }
    fixture.step { fixture.editor.setBounds(id: placement.id, to: target, actionName: "Move Signature") }
    #expect(fixture.document.signaturePlacements.first?.bounds == target)
    #expect(fixture.undoManager.undoActionName == "Move Signature")

    fixture.undoManager.undo()
    #expect(fixture.document.signaturePlacements.first?.bounds == placement.bounds)

    fixture.undoManager.redo()
    #expect(fixture.document.signaturePlacements.first?.bounds == target)
}

@MainActor
@Test func resizeUndoRestoresPreviousSize() {
    let fixture = EditingFixture()
    let placement = EditingFixture.placement(x: 10)
    let larger = CGRect(x: 10, y: 10, width: 360, height: 120)

    fixture.step { fixture.editor.add(placement) }
    fixture.step { fixture.editor.setBounds(id: placement.id, to: larger, actionName: "Resize Signature") }
    #expect(fixture.undoManager.undoActionName == "Resize Signature")

    fixture.undoManager.undo()
    #expect(fixture.document.signaturePlacements.first?.bounds == placement.bounds)
}

@MainActor
@Test func unchangedBoundsRegisterNoUndo() {
    let fixture = EditingFixture()
    let placement = EditingFixture.placement(x: 10)

    fixture.step {
        fixture.editor.add(placement)
        fixture.editor.setBounds(id: placement.id, to: placement.bounds, actionName: "Move Signature")
    }

    // A registered move would have renamed the group and left a second action to undo.
    #expect(fixture.undoManager.undoActionName == "Add Signature")
    fixture.undoManager.undo()
    #expect(fixture.document.signaturePlacements.isEmpty)
    #expect(!fixture.undoManager.canUndo)
}

@MainActor
@Test func deleteUndoRestoresPlacementAtOriginalIndex() {
    let fixture = EditingFixture()
    let first = EditingFixture.placement(x: 10)
    let second = EditingFixture.placement(x: 200)
    let third = EditingFixture.placement(x: 400)

    fixture.step { fixture.editor.add(first) }
    fixture.step { fixture.editor.add(second) }
    fixture.step { fixture.editor.add(third) }
    fixture.step { fixture.editor.delete(id: second.id) }
    #expect(fixture.document.signaturePlacements == [first, third])
    #expect(fixture.undoManager.undoActionName == "Remove Signature from Page")

    fixture.undoManager.undo()
    #expect(fixture.document.signaturePlacements == [first, second, third])

    fixture.undoManager.redo()
    #expect(fixture.document.signaturePlacements == [first, third])
}

@MainActor
@Test func modelUpdatesBoundsAndReportsPreviousValue() {
    var document = PDFViewerDocument()
    let placement = EditingFixture.placement(x: 10)
    document.addSignaturePlacement(placement)

    let previous = document.updatePlacementBounds(id: placement.id, to: CGRect(x: 1, y: 2, width: 3, height: 4))
    #expect(previous == placement.bounds)
    #expect(document.signaturePlacements.first?.bounds == CGRect(x: 1, y: 2, width: 3, height: 4))
    #expect(document.updatePlacementBounds(id: UUID(), to: .zero) == nil)
}
