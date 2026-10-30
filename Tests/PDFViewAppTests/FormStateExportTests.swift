import AppKit
@preconcurrency import Quartz
import Testing
@testable import PDFViewApp

@MainActor
struct FormStateExportTests {
    @Test func editDuringSuspendedScanStillWarnsOnClose() async throws {
        let source = try ExportFixture.document(mediaBoxes: Array(
            repeating: CGRect(x: 0, y: 0, width: 400, height: 600), count: 20
        ))
        let field = try ExportFixture.textField(on: #require(source.page(at: 19)))
        let model = PDFViewerDocument(pdfDocument: source)
        let protection = DocumentProtection(
            document: source, formBaseline: model.formBaseline, initialFormValues: model.initialFormValues
        )
        let closeGuard = DocumentCloseGuard()
        closeGuard.unsavedWork = {
            SigningFlowLogic.unsavedWork(
                placements: [],
                exported: nil,
                formValues: protection.formBaseline?.values(),
                savedFormValues: protection.initialFormValues
            )
        }
        #expect(!closeGuard.hasUnsavedWork)
        var editedDuringScan = false
        var batches = 0
        let editAfterBatch: ([SignatureField]) -> Void = { _ in
            batches += 1
            if batches == 1 {
                Task { @MainActor in
                    #expect(batches < 20)
                    field.widgetStringValue = "Typed before the last batch"
                    editedDuringScan = true
                    #expect(closeGuard.hasUnsavedWork)
                }
            }
        }
        _ = try await ReaderController.scanSignatureFields(in: source, batchSize: 1, batch: editAfterBatch)
        #expect(editedDuringScan)
        #expect(closeGuard.hasUnsavedWork)
        #expect(model.initialFormValues?.first?.stringValue == "Baseline value")
    }

    @Test(arguments: [false, true])
    func saveCompletionRequiresBothPlacementsAndFormsToMatch(changePlacements: Bool) async throws {
        let source = try ExportFixture.document()
        let field = try ExportFixture.textField(on: #require(source.page(at: 0)))
        let model = try ExportFixture.model(source)
        var livePlacements = model.signaturePlacements
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".pdf")
        defer { try? FileManager.default.removeItem(at: url) }
        let exported = try await SignedPDFExporter.writeAsync(source, placements: livePlacements, to: url) { progress in
            if progress.stage == .rendering, progress.completedPages == 1 {
                if changePlacements {
                    livePlacements = []
                } else {
                    field.widgetStringValue = "Typed during export"
                }
            }
        }
        #expect(exported.placements == model.signaturePlacements)
        #expect(exported.formValues.first?.stringValue == "Baseline value")
        #expect(!exported.matches(placements: livePlacements, formValues: FormScan.capture(source)?.values()))
        #expect(!exported.matches(placements: exported.placements, formValues: nil))
        #expect(exported.matches(placements: exported.placements, formValues: exported.formValues))
        let guardForClose = DocumentCloseGuard()
        guardForClose.unsavedWork = {
            SigningFlowLogic.unsavedWork(
                placements: livePlacements,
                exported: exported.placements,
                formValues: FormScan.capture(source)?.values(),
                savedFormValues: exported.formValues
            )
        }
        #expect(guardForClose.hasUnsavedWork)
        let saved = try #require(PDFDocument(url: url))
        #expect(saved.string?.contains("Baseline value") == true)
        #expect(saved.string?.contains("Typed during export") == false)
    }

    @Test(arguments: [false, true])
    func baselineIsCapturedOnceAfterUnlock(native: Bool) throws {
        let source = try ExportFixture.document()
        _ = try ExportFixture.textField(on: #require(source.page(at: 0)))
        let data = try #require(source.dataRepresentation(options: [
            PDFDocumentWriteOption.userPasswordOption: "reader", PDFDocumentWriteOption.ownerPasswordOption: "owner",
        ]))
        let locked = try #require(PDFDocument(data: data))
        let protection = DocumentProtection(document: locked)
        #expect(protection.initialFormValues == nil)
        if native {
            #expect(locked.unlock(withPassword: "reader"))
        } else {
            #expect(protection.unlock(withPassword: "reader"))
        }
        #expect(protection.initialFormValues != nil)
        let baseline = protection.initialFormValues
        let field = try #require(protection.formBaseline?.widgets.first)
        field.widgetStringValue = "Changed after unlock"
        protection.refresh()
        #expect(protection.initialFormValues == baseline)
        #expect(protection.formBaseline?.values() != baseline)
    }

    @Test func quitReviewIncludesInvisibleDocumentWindows() {
        let document = NSWindow(
            contentRect: .zero,
            styleMask: [.titled, .miniaturizable],
            backing: .buffered,
            defer: true
        )
        let utility = NSWindow(contentRect: .zero, styleMask: .titled, backing: .buffered, defer: true)
        document.isReleasedWhenClosed = false
        utility.isReleasedWhenClosed = false
        defer { document.close()
            utility.close()
        }
        let closeGuard = DocumentCloseGuard()
        closeGuard.unsavedWork = { UnsavedWork(formEntries: true) }
        closeGuard.install(on: document)
        document.orderOut(nil)
        #expect(!document.isVisible)
        #expect(AppDelegate.documentGuards(in: [document, utility]) == [closeGuard])
        document.miniaturize(nil)
        #expect(AppDelegate.documentGuards(in: [document, utility]).contains { $0.hasUnsavedWork })
    }

    @Test func dateCacheRollsOverForDayLocaleAndTimeZone() throws {
        let date = Date(timeIntervalSince1970: 0)
        let zone = try #require(TimeZone(secondsFromGMT: 0))
        func artwork(_ date: Date, locale: String = "en_US", zone: TimeZone) throws -> StampArtwork {
            try #require(StampArtwork.make(
                kind: .date,
                signature: nil,
                initials: nil,
                date: date,
                locale: Locale(identifier: locale),
                timeZone: zone
            ))
        }
        let first = try artwork(date, zone: zone)
        #expect(try artwork(date.addingTimeInterval(3600), zone: zone).pngData == first.pngData)
        #expect(try artwork(date.addingTimeInterval(86400), zone: zone).dateText != first.dateText)
        #expect(try artwork(date, locale: "sv_SE", zone: zone).dateText != first.dateText)
        #expect(try artwork(date, zone: #require(TimeZone(secondsFromGMT: -3600))).dateText != first.dateText)
    }
}
