import AppKit
@preconcurrency import Quartz
import Testing
@testable import PDFViewApp

@MainActor
struct WidgetCaptureLatencyTests {
    @Test func widgetHeavyCaptureLatency() async throws {
        if ProcessInfo.processInfo.environment["PDFVIEW_WIDGET_LATENCY_CHILD"] == "1" {
            try measureCapture()
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

    private func measureCapture() throws {
        let source = try ExportFixture.document(mediaBoxes: Array(
            repeating: CGRect(x: 0, y: 0, width: 400, height: 600), count: 300
        ))
        for index in 0 ..< 2000 {
            let page = try #require(source.page(at: index % 300))
            let field = ExportFixture.textField(on: page)
            field.fieldName = "Field\(index)"
        }
        let fixtureData = try #require(source.dataRepresentation())
        let cold = try #require(PDFDocument(data: fixtureData))
        let clock = ContinuousClock()
        let start = clock.now
        let model = PDFViewerDocument(pdfDocument: cold)
        let open = start.duration(to: clock.now)
        let saveStart = clock.now
        let values = FormScan.capture(cold)?.values()
        let save = saveStart.duration(to: clock.now)
        print("300-page / 2000-widget form capture: open=\(open), save=\(save)")
        #expect(model.initialFormValues?.count == 2000)
        #expect(values == model.initialFormValues)
        // Capture at open includes PDFKit's lazy annotation parse of every page and measured
        // 47-103 ms for this fixture depending on machine load; 250 ms catches a real regression
        // (a noticeable stall) without failing on a busy machine.
        #expect(open < .milliseconds(250))
        #expect(save < .milliseconds(100))
    }
}

private final class WidgetCaptureBundle: NSObject {}
