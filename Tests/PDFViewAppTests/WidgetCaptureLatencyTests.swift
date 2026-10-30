import AppKit
@preconcurrency import Quartz
import Testing
@testable import PDFViewApp

@MainActor
struct WidgetCaptureLatencyTests {
    @Test func widgetHeavyCaptureLatency() async throws {
        if ProcessInfo.processInfo.environment["PDFVIEW_WIDGET_LATENCY_CHILD"] == "1" {
            try await measureCapture()
        } else {
            let result = try await runIsolated()
            print(result.output)
            #expect(result.status == 0, "Isolated form-capture regression failed: \(result.output)")
            #expect(result.output.contains("2000-widget form capture:"))
        }
    }

    /// Keep unrelated suites' concurrent PDFKit fixture/export work out of this measurement,
    /// following ExportLatencyTests' existing isolated-process pattern.
    private func runIsolated() async throws -> (status: Int32, output: String) {
        let executable = try #require(Bundle.main.executableURL)
        let bundle = try #require(Bundle(for: WidgetCaptureBundle.self).executableURL)
        return try await Task.detached {
            let process = Process()
            process.executableURL = executable
            process.arguments = [
                "--test-bundle-path", bundle.path, "--filter", "WidgetCaptureLatencyTests",
                bundle.path, "--testing-library", "swift-testing",
            ]
            var environment = ProcessInfo.processInfo.environment
            environment["PDFVIEW_WIDGET_LATENCY_CHILD"] = "1"
            process.environment = environment
            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = pipe
            try process.run()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            return (process.terminationStatus, String(data: data, encoding: .utf8) ?? "Invalid test output")
        }.value
    }

    private func measureCapture() async throws {
        let cold = try widgetHeavyDocument()
        let clock = ContinuousClock()
        let start = clock.now
        let model = PDFViewerDocument(pdfDocument: cold)
        let open = start.duration(to: clock.now)
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".pdf")
        defer { try? FileManager.default.removeItem(at: url) }
        let saveStart = clock.now
        var firstSuspension: Duration?
        var last = saveStart
        var maximumGap = Duration.zero
        let heartbeat = Task { @MainActor in
            firstSuspension = saveStart.duration(to: clock.now)
            while !Task.isCancelled {
                let now = clock.now
                maximumGap = max(maximumGap, last.duration(to: now))
                last = now
                try? await Task.sleep(for: .milliseconds(10))
            }
        }
        defer { heartbeat.cancel() }
        let state = try await SignedPDFExporter.writeAsync(cold, placements: [], to: url) { _ in }
        maximumGap = max(maximumGap, last.duration(to: clock.now))
        let save = try #require(firstSuspension)
        let values = state.formValues
        print(
            "300-page / 2000-widget form capture: open=\(open), save-to-first-suspension=\(save), max-gap=\(maximumGap)"
        )
        #expect(model.initialFormValues?.count == 2000)
        #expect(values == model.initialFormValues)
        // Capture at open includes PDFKit's lazy annotation parse of every page and measured
        // 47-103 ms for this fixture depending on machine load; 250 ms catches a real regression
        // (a noticeable stall) without failing on a busy machine.
        #expect(open < .milliseconds(250))
        #expect(save < .milliseconds(100))
        #expect(maximumGap < .milliseconds(250))
    }

    private func widgetHeavyDocument() throws -> PDFDocument {
        let source = try ExportFixture.document(mediaBoxes: Array(
            repeating: CGRect(x: 0, y: 0, width: 400, height: 600), count: 300
        ))
        for index in 0 ..< 2000 {
            let page = try #require(source.page(at: index % 300))
            let field = ExportFixture.textField(on: page)
            field.fieldName = "Field\(index)"
        }
        let fixtureData = try #require(source.dataRepresentation())
        return try #require(PDFDocument(data: fixtureData))
    }
}

private final class WidgetCaptureBundle: NSObject {}
