import AppKit
import Testing
@testable import PDFViewApp

@MainActor
struct SignatureDrawingTests {
    @Test func strokesUseUndoManagerAndRedo() {
        let manager = UndoManager()
        manager.groupsByEvent = false
        let drawing = SignatureDrawingState(keepsExistingArtwork: true)
        drawing.undoManager = manager
        let stroke = [CGPoint(x: 10, y: 20)]
        drawing.append(stroke)
        #expect(drawing.strokes == [stroke])
        #expect(!drawing.keepsExistingArtwork)
        #expect(manager.undoActionName == "Stroke")
        manager.undo()
        #expect(drawing.strokes.isEmpty)
        #expect(drawing.keepsExistingArtwork)
        manager.redo()
        #expect(drawing.strokes == [stroke])
        #expect(!drawing.keepsExistingArtwork)
    }

    @Test func clearRestoresStrokesAndSavedArtwork() {
        let manager = UndoManager()
        manager.groupsByEvent = false
        let drawing = SignatureDrawingState(keepsExistingArtwork: true)
        drawing.undoManager = manager
        drawing.clear()
        #expect(!drawing.keepsExistingArtwork)
        manager.undo()
        #expect(drawing.keepsExistingArtwork)
        drawing.append([CGPoint(x: 1, y: 1)])
        drawing.append([CGPoint(x: 2, y: 2)])
        drawing.clear()
        #expect(drawing.strokes.isEmpty)
        manager.undo()
        #expect(drawing.strokes.count == 2)
        manager.undo()
        #expect(drawing.strokes.count == 1)
    }

    @Test func emptyStrokeDoesNotReplaceSavedArtworkOrRegisterUndo() {
        let manager = UndoManager()
        let drawing = SignatureDrawingState(keepsExistingArtwork: true)
        drawing.undoManager = manager
        drawing.append([])
        #expect(!manager.canUndo)
        #expect(drawing.keepsExistingArtwork)
    }
}
