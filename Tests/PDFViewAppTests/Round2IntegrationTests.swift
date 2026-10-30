import AppKit
import Quartz
import SwiftUI
import Testing
@testable import PDFViewApp

@MainActor
struct Round2IntegrationTests {
    private let phrase = UUID().uuidString

    @Test func protectionFollowsIdentityAndCancelCanBeReopened() throws {
        let source = try encryptedForm()
        let session = DocumentProtectionSession()
        session.attach(source)
        let protection = try #require(session.protection)
        #expect(session.showsUnlock)
        session.showsUnlock = false
        session.attach(source)
        #expect(session.protection === protection)
        #expect(!session.showsUnlock)
        session.requestUnlock()
        #expect(session.showsUnlock)
        #expect(protection.unlock(withPassword: phrase))
        session.refresh()
        #expect(!session.showsUnlock)
        #expect(protection.exportPassword == phrase)
        try session.attach(encryptedForm())
        #expect(session.protection !== protection)
        #expect(session.protection?.knownPassword == nil)
        #expect(session.showsUnlock)
        session.attach(nil)
        #expect(session.protection == nil)
        #expect(!session.showsUnlock)
    }

    @Test func nativeUnlockRefreshesWithoutInventingPassword() throws {
        let source = try encryptedForm()
        let session = DocumentProtectionSession()
        session.attach(source)
        #expect(source.unlock(withPassword: phrase))
        session.refresh()
        #expect(session.protection?.isLocked == false)
        #expect(!session.showsUnlock)
        #expect(session.protection?.exportNotice.contains("password is unknown") == true)
    }

    @Test(arguments: [StampKind.signature, .initials, .date])
    func placementsCaptureKindAndTheirOwnArtwork(kind: StampKind) throws {
        let signature = try profile(text: "Jane Doe")
        let initials = try profile(text: "JD")
        let date = Date(timeIntervalSince1970: 0)
        let locale = Locale(identifier: "en_US")
        let timeZone = try #require(TimeZone(secondsFromGMT: 0))
        let artwork = try #require(StampArtwork.make(
            kind: kind, signature: signature, initials: initials, date: date, locale: locale, timeZone: timeZone
        ))
        let placement = artwork.placement(pageIndex: 1, bounds: ExportFixture.marker)
        #expect(placement.kind == kind)
        #expect(placement.signaturePNGData == artwork.pngData)
        #expect(NSImage(data: placement.signaturePNGData) != nil)
        if kind == .date {
            #expect(placement.dateText == "Jan 1, 1970")
            #expect(placement.signaturePNGData == SignatureRenderer.renderDate(
                date, locale: locale, timeZone: timeZone
            )?.pngData)
        } else {
            #expect(placement.signerName == "Jane Doe")
            #expect(placement.signaturePNGData == (kind == .initials ? initials : signature).signaturePNGData)
        }
        let label = StampAccessibility.label(
            signerName: placement.signerName,
            pageIndex: 1,
            bounds: placement.bounds,
            cropBox: CGRect(x: 0, y: 0, width: 400, height: 600),
            fields: [],
            kind: placement.kind,
            dateText: placement.dateText
        )
        let prefix = kind == .date ? "Date Jan 1, 1970" : "\(kind.title) by Jane Doe"
        #expect(label.hasPrefix("\(prefix), page 2,"))
    }

    @Test func missingInitialsRequiresSetupAndDateNeedsNoProfile() {
        #expect(StampArtwork.make(kind: .initials, signature: nil, initials: nil) == nil)
        #expect(StampKind.initials.profileKind == .initials)
        #expect(StampKind.date.profileKind == nil)
        #expect(StampArtwork.make(kind: .date, signature: nil, initials: nil) != nil)
    }

    @Test func scanDiscardsReplacedDocumentAndRestartsOnUnlock() async throws {
        let original = try makeSignableForm()
        let locked = try encryptedForm()
        let recorder = StateRecorder()
        let coordinator = makeRepresentable(document: original, recorder: recorder).makeCoordinator()
        let view = SigningPDFView()
        coordinator.attach(to: view)
        view.document = original
        coordinator.documentDidChange(original)
        view.document = locked
        coordinator.documentDidChange(locked)
        for _ in 0 ..< 100 {
            await Task.yield()
        }
        let allLocked = recorder.states.allSatisfy(\.isLocked)
        #expect(allLocked)
        #expect(coordinator.signatureFields.isEmpty)
        #expect(locked.unlock(withPassword: phrase))
        for _ in 0 ..< 200 where recorder.states.last?.formValues == nil {
            await Task.yield()
        }
        #expect(recorder.states.last?.isLocked == false)
        #expect(coordinator.signatureFields.map(\.name) == ["ClientSignature"])
        #expect(coordinator.formScan?.widgets.map(\.fieldName) == ["Name"])
    }

    @Test func protectedPrintUnlocksAndCleansTemporaryCopy() async throws {
        let source = try encryptedForm()
        let protection = DocumentProtection(document: source)
        #expect(protection.unlock(withPassword: phrase))
        let model = try ExportFixture.model(source)
        let printing = PDFPrinting()
        defer { printing.cleanup() }
        let selected = protection.exportPassword
        try await printing.prepare(source: source, placements: model.signaturePlacements, password: selected) { _ in }
        let url = try #require(printing.temporaryURL)
        #expect(PDFDocument(url: url)?.isLocked == true)
        #expect(printing.document?.isLocked == false)
        #expect(try ExportFixture.colorBounds(on: #require(printing.document?.page(at: 0)), red: true)
            == ExportFixture.marker)
        printing.cleanup()
        #expect(!FileManager.default.fileExists(atPath: url.path))
    }

    @Test(arguments: [0, 1, 2])
    func saveConfigurationReachesWriteAndGuardsByteLoadedOriginal(choice: Int) async throws {
        let source = try encryptedForm()
        let protection = DocumentProtection(document: source)
        if choice == 2 {
            #expect(source.unlock(withPassword: phrase))
            protection.refresh()
            #expect(protection.exportNotice.contains("password is unknown"))
        } else {
            #expect(protection.unlock(withPassword: phrase))
        }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".pdf")
        defer { try? FileManager.default.removeItem(at: url) }
        let operation = SignedCopyOperation()
        #expect(operation.reserve())
        let panel = NSSavePanel()
        operation.configure(panel, originalURL: url, protection: protection)
        #expect(panel.accessoryView != nil)
        // SwiftUI byte-loaded documents have no PDFKit URL; configuration must still guard the original.
        #expect(source.documentURL == nil)
        let rejection = await withCheckedContinuation { continuation in
            operation.write(source, placements: [], to: url) { continuation.resume(returning: $0) }
        }
        if case let .failure(error) = rejection {
            #expect(error as? PDFViewerDocument.ExportError == .cannotReplaceOriginal)
        } else {
            Issue.record("Configured original should be rejected")
        }
        #expect(!FileManager.default.fileExists(atPath: url.path))
        #expect(operation.reserve())
        operation.configure(panel, originalURL: nil, protection: protection)
        // The accessory's selection is read at write time, after the save panel returns.
        protection.keepPasswordProtection = choice != 1
        let result = await withCheckedContinuation { continuation in
            operation.write(source, placements: [], to: url) { continuation.resume(returning: $0) }
        }
        _ = try result.get()
        let saved = try #require(PDFDocument(url: url))
        #expect(saved.isEncrypted == (choice == 0))
        if saved.isLocked {
            #expect(saved.unlock(withPassword: phrase))
        }
        #expect(saved.pageCount == source.pageCount)
    }

    @Test(arguments: [StampKind.initials, .date])
    func stampEditingUndoAndExportPreserveArtwork(kind: StampKind) async throws {
        let artwork = try #require(StampArtwork.make(
            kind: kind, signature: nil, initials: profile(text: "JD")
        ))
        var model = try PDFViewerDocument(pdfDocument: ExportFixture.document())
        let placement = artwork.placement(pageIndex: 0, bounds: CGRect(x: 20, y: 20, width: 180, height: 60))
        let editor = SignaturePlacementEditor()
        editor.document = Binding(get: { model }, set: { model = $0 })
        let undo = UndoManager()
        undo.groupsByEvent = false
        editor.undoManager = undo
        undo.beginUndoGrouping()
        editor.add(placement)
        undo.endUndoGrouping()
        let resized = CGRect(x: 25, y: 25, width: 360, height: 120)
        undo.beginUndoGrouping()
        editor.setBounds(id: placement.id, to: resized, actionName: "Resize Stamp")
        undo.endUndoGrouping()
        undo.undo()
        #expect(model.signaturePlacements.last == placement)
        undo.undo()
        #expect(!model.signaturePlacements.contains { $0.id == placement.id })
        undo.redo()
        #expect(model.signaturePlacements.last == placement)
        #expect(SigningFlowLogic.adjacentPlacement(after: nil, in: [placement], forward: true) == placement.id)
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".pdf")
        defer { try? FileManager.default.removeItem(at: url) }
        try await model.writeSignedCopy(to: url)
        let output = try #require(PDFDocument(url: url))
        let saved = try #require(output.page(at: 0))
        let stamped = saved.thumbnail(of: CGSize(width: 400, height: 600), for: .mediaBox).tiffRepresentation
        model.signaturePlacements = []
        try await model.writeSignedCopy(to: url)
        let baseline = try #require(PDFDocument(url: url))
        let blank = try #require(baseline.page(at: 0))
        #expect(stamped != blank.thumbnail(of: CGSize(width: 400, height: 600), for: .mediaBox).tiffRepresentation)
    }

    private func encryptedForm() throws -> PDFDocument {
        let source = try makeSignableForm()
        let data = try #require(source.dataRepresentation(options: [
            PDFDocumentWriteOption.userPasswordOption: phrase,
            PDFDocumentWriteOption.ownerPasswordOption: UUID().uuidString,
        ]))
        return try #require(PDFDocument(data: data))
    }

    private func profile(text: String) throws -> SignatureProfile {
        let rendering = try #require(SignatureRenderer.renderText(text, fontName: "SnellRoundhand"))
        return SignatureProfile(fullName: "Jane Doe", signaturePNGData: rendering.pngData, sourceKind: .type)
    }
}
