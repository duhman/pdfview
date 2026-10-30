import CoreGraphics
import Foundation
@preconcurrency import Quartz
import Testing
@testable import PDFViewApp

@MainActor
struct ExportLatencyTests {
    @Test func heartbeatStaysBoundedThroughImageHeavy300PageExport() async throws {
        if ProcessInfo.processInfo.environment["PDFVIEW_LATENCY_CHILD"] == "1" {
            try await measureHeartbeat()
        } else {
            let result = try await runIsolated()
            print(result.output)
            #expect(result.status == 0, "Isolated heartbeat regression failed: \(result.output)")
        }
    }

    /// Other suites deliberately do synchronous PDFKit fixture/render work on main. Reuse the
    /// current SwiftPM test host in a child process so their work cannot count as exporter latency.
    private func runIsolated() async throws -> (status: Int32, output: String) {
        let executable = try #require(Bundle.main.executableURL)
        let bundle = try #require(Bundle(for: LatencyBundle.self).executableURL)
        return try await Task.detached {
            let process = Process()
            process.executableURL = executable
            process.arguments = [
                "--test-bundle-path", bundle.path, "--filter", "ExportLatencyTests",
                bundle.path, "--testing-library", "swift-testing",
            ]
            var environment = ProcessInfo.processInfo.environment
            environment["PDFVIEW_LATENCY_CHILD"] = "1"
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

    private func measureHeartbeat() async throws {
        let source = try imageHeavyDocument()
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".pdf")
        defer { try? FileManager.default.removeItem(at: url) }
        let clock = ContinuousClock()
        var last = clock.now
        var gaps: [ExportProgress.Stage: Duration] = [:]
        var ticks: [ExportProgress.Stage: Int] = [:]
        var stage = ExportProgress.Stage.rendering
        func beat() {
            let now = clock.now
            gaps[stage] = max(gaps[stage, default: .zero], last.duration(to: now))
            last = now
        }
        let heartbeat = Task { @MainActor in
            while !Task.isCancelled {
                beat()
                ticks[stage, default: 0] += 1
                try? await Task.sleep(for: .milliseconds(10))
            }
        }
        defer { heartbeat.cancel() }
        try await SignedPDFExporter.writeAsync(source, placements: [], to: url) { progress in
            beat()
            stage = progress.stage
        }
        beat()
        #expect(ticks[.rendering, default: 0] > 10)
        #expect(ticks[.writing, default: 0] > 1)
        for stage in [ExportProgress.Stage.rendering, .writing, .restoringGeometry, .validating] {
            #expect(gaps[stage, default: .zero] < .milliseconds(250), "\(stage): \(gaps[stage, default: .zero])")
        }
        print("300-page image-heavy heartbeat maximum gaps: \(gaps)")
        #expect(PDFDocument(url: url)?.pageCount == 300)
    }

    private func imageHeavyDocument() throws -> PDFDocument {
        let side = 512
        let data = NSMutableData()
        let consumer = try #require(CGDataConsumer(data: data))
        var media = CGRect(x: 0, y: 0, width: 1024, height: 1024)
        let context = try #require(CGContext(consumer: consumer, mediaBox: &media, nil))
        var pixels = noisyPixels(side: side)
        for index in 0 ..< 300 {
            pixels[0] = UInt8(truncatingIfNeeded: index)
            pixels[1] = UInt8(truncatingIfNeeded: index >> 8)
            let image = try noisyImage(side: side, pixels: pixels)
            context.beginPDFPage(nil)
            for x in [0, 512] {
                for y in [0, 512] {
                    context.draw(image, in: CGRect(x: x, y: y, width: side, height: side))
                }
            }
            context.endPDFPage()
        }
        context.closePDF()
        return try #require(PDFDocument(data: data as Data))
    }

    private func noisyPixels(side: Int) -> Data {
        var seed: UInt32 = 42
        return Data((0 ..< side * side * 3).map { _ -> UInt8 in
            seed = 1_664_525 &* seed &+ 1_013_904_223
            return UInt8(truncatingIfNeeded: seed >> 24)
        })
    }

    private func noisyImage(side: Int, pixels: Data) throws -> CGImage {
        let provider = try #require(CGDataProvider(data: pixels as CFData))
        return try #require(CGImage(
            width: side,
            height: side,
            bitsPerComponent: 8,
            bitsPerPixel: 24,
            bytesPerRow: side * 3,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: [],
            provider: provider,
            decode: nil,
            shouldInterpolate: false,
            intent: .defaultIntent
        ))
    }
}

private final class LatencyBundle: NSObject {}
