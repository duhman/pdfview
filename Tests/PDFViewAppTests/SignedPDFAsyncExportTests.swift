import Foundation
import Quartz
import Testing
@testable import PDFViewApp

@MainActor
struct SignedPDFAsyncExportTests {
    @Test func reportsEveryPageAndPreservesSignedContent() async throws {
        let source = try ExportFixture.document(mediaBoxes: Array(
            repeating: CGRect(x: 0, y: 0, width: 400, height: 600), count: 12
        ))
        let model = try ExportFixture.model(source)
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("signed.pdf")
        var progress: [ExportProgress] = []
        try await SignedPDFExporter.writeAsync(source, placements: model.signaturePlacements, to: url) {
            progress.append($0)
        }
        #expect(progress.filter { $0.stage == .rendering }.map(\.completedPages) == Array(0 ... 12))
        #expect(progress.allSatisfy { $0.totalPages == 12 })
        let output = try #require(PDFDocument(url: url))
        #expect(output.pageCount == 12)
        #expect(try ExportFixture.colorBounds(on: #require(output.page(at: 0)), red: true) == ExportFixture.marker)
    }

    @Test func yieldsToOtherMainActorWorkDuring300PageExport() async throws {
        let source = try ExportFixture.document(mediaBoxes: Array(
            repeating: CGRect(x: 0, y: 0, width: 400, height: 600), count: 300
        ))
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".pdf")
        defer { try? FileManager.default.removeItem(at: url) }
        var completed = 0
        var heartbeatPage: Int?
        try await SignedPDFExporter.writeAsync(source, placements: [], to: url) { progress in
            completed = progress.completedPages
            if completed == 1 {
                Task { @MainActor in heartbeatPage = completed }
            }
        }
        #expect(try #require(heartbeatPage) < 300)
        #expect(PDFDocument(url: url)?.pageCount == 300)
    }

    @Test func cancellationAfterLastPageDoesNotCreateDestination() async throws {
        let source = try ExportFixture.document()
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".pdf")
        defer { try? FileManager.default.removeItem(at: url) }
        let task = Task { @MainActor in
            try await SignedPDFExporter.writeAsync(source, placements: [], to: url) { progress in
                if progress.completedPages == progress.totalPages {
                    withUnsafeCurrentTask { $0?.cancel() }
                }
            }
        }
        do {
            _ = try await task.value
            Issue.record("Expected cancellation")
        } catch is CancellationError {
            #expect(!FileManager.default.fileExists(atPath: url.path))
        }
    }

    @Test func asyncPathPreservesOffsetGeometryRotationAndOutline() async throws {
        let source = try ExportFixture.document(mediaBoxes: [CGRect(x: -20, y: -30, width: 400, height: 600)])
        let page = try #require(source.page(at: 0))
        page.rotation = 90
        let root = PDFOutline()
        let chapter = PDFOutline()
        chapter.label = "Chapter"
        chapter.destination = PDFDestination(page: page, at: CGPoint(x: 30, y: 400))
        root.insertChild(chapter, at: 0)
        source.outlineRoot = root
        let model = try ExportFixture.model(source)
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".pdf")
        defer { try? FileManager.default.removeItem(at: url) }
        try await SignedPDFExporter.writeAsync(source, placements: model.signaturePlacements, to: url) { _ in }
        let output = try #require(PDFDocument(url: url))
        let result = try #require(output.page(at: 0))
        #expect(result.rotation == 90)
        #expect(result.bounds(for: .mediaBox) == page.bounds(for: .mediaBox))
        #expect(output.outlineRoot?.child(at: 0)?.destination?.page === result)
        #expect(try ExportFixture.colorBounds(on: result, red: true) == ExportFixture.marker)
    }

    @Test func cancellationLeavesExistingDestinationUntouched() async throws {
        let source = try ExportFixture.document(mediaBoxes: Array(
            repeating: CGRect(x: 0, y: 0, width: 400, height: 600), count: 12
        ))
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("signed.pdf")
        let sentinel = Data("original destination".utf8)
        try sentinel.write(to: url)
        let task = Task { @MainActor in
            try await SignedPDFExporter.writeAsync(source, placements: [], to: url) { progress in
                if progress.completedPages == 3 {
                    withUnsafeCurrentTask { $0?.cancel() }
                }
            }
        }
        do {
            _ = try await task.value
            Issue.record("Expected cancellation")
        } catch is CancellationError {
            #expect(try Data(contentsOf: url) == sentinel)
        }
        #expect(try FileManager.default.contentsOfDirectory(atPath: directory.path) == ["signed.pdf"])
    }
}
