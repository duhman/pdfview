import AppKit
@preconcurrency import Quartz
import Testing
@testable import PDFViewApp

/// Annotations whose look lives only in an /AP appearance stream: another party's visible
/// signature, image stamps, custom checkbox art. A signed copy must keep them as they look.
@MainActor
struct AppearanceStreamExportTests {
    private static let probes: [(name: String, rect: CGRect)] = [
        ("Stamp drawn only by its appearance", CGRect(x: 12, y: 12, width: 76, height: 76)),
        ("Checkbox with custom appearance", CGRect(x: 112, y: 112, width: 76, height: 76)),
        ("Ink", CGRect(x: 12, y: 112, width: 76, height: 76)),
        ("Prior signer's visible signature", CGRect(x: 112, y: 12, width: 76, height: 76)),
        ("Checkbox with appearance and colours", CGRect(x: 62, y: 62, width: 76, height: 76)),
    ]

    @Test
    func signedCopyKeepsAppearanceStreams() async throws {
        let source = try #require(PDFDocument(data: Self.fixture()))
        let destination = FileManager.default.temporaryDirectory
            .appendingPathComponent("appearance-\(UUID().uuidString).pdf")
        defer { try? FileManager.default.removeItem(at: destination) }

        _ = try await SignedPDFExporter.writeAsync(source, placements: [], to: destination) { _ in }
        let exported = try #require(PDFDocument(url: destination))

        for probe in Self.probes {
            let before = try Self.inkedPixels(source, in: probe.rect)
            let after = try Self.inkedPixels(exported, in: probe.rect)
            #expect(before > 1000, "\(probe.name) should be drawn in the source")
            #expect(Double(after) >= Double(before) * 0.95, "\(probe.name): \(before) -> \(after) inked pixels")
        }
    }

    private static func inkedPixels(_ document: PDFDocument, in rect: CGRect) throws -> Int {
        let page = try #require(document.page(at: 0))
        let context = try #require(CGContext(
            data: nil,
            width: 200,
            height: 200,
            bitsPerComponent: 8,
            bytesPerRow: 800,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        context.setFillColor(CGColor.white)
        context.fill(CGRect(x: 0, y: 0, width: 200, height: 200))
        page.draw(with: .mediaBox, to: context)
        let pixels = try #require(context.data).assumingMemoryBound(to: UInt8.self)
        var count = 0
        for y in Int(rect.minY) ..< Int(rect.maxY) {
            for x in Int(rect.minX) ..< Int(rect.maxX) {
                let index = ((199 - y) * 200 + x) * 4
                if pixels[index] < 240 || pixels[index + 1] < 240 || pixels[index + 2] < 240 {
                    count += 1
                }
            }
        }
        return count
    }

    /// A hand-written 200 x 200 pt page: every annotation is a solid fill drawn only by its /AP stream.
    private static func fixture() -> Data {
        let form = "/Type /XObject /Subtype /Form /FormType 1 /BBox [0 0 80 80] /Resources << >>"
        let objects = [
            "<< /Type /Catalog /Pages 2 0 R /AcroForm << /Fields [7 0 R 12 0 R 14 0 R] /SigFlags 3 >> >>",
            "<< /Type /Pages /Kids [3 0 R] /Count 1 >>",
            "<< /Type /Page /Parent 2 0 R /MediaBox [0 0 200 200] /Contents 4 0 R "
                + "/Annots [5 0 R 7 0 R 10 0 R 12 0 R 14 0 R] >>",
            stream("", dictionary: ""),
            "<< /Type /Annot /Subtype /Stamp /Name /Draft /Rect [10 10 90 90] /F 4 /AP << /N 6 0 R >> >>",
            stream("1 0 0 rg 0 0 80 80 re f", dictionary: form),
            "<< /Type /Annot /Subtype /Widget /FT /Btn /T (cb) /Rect [110 110 190 190] /F 4 /V /Yes /AS /Yes "
                + "/AP << /N << /Yes 8 0 R /Off 9 0 R >> >> >>",
            stream("0 0 1 rg 0 0 80 80 re f", dictionary: form),
            stream("", dictionary: form),
            "<< /Type /Annot /Subtype /Ink /Rect [10 110 90 190] /F 4 /InkList [[15 115 85 185]] /C [0 1 0] "
                + "/AP << /N 11 0 R >> >>",
            stream("0 1 0 RG 4 w 5 5 m 75 75 l S", dictionary: form),
            "<< /Type /Annot /Subtype /Widget /FT /Sig /T (PriorSigner) /Rect [110 10 190 90] /F 4 "
                + "/AP << /N 13 0 R >> >>",
            stream("1 0 1 rg 0 0 80 80 re f", dictionary: form),
            "<< /Type /Annot /Subtype /Widget /FT /Btn /T (cbmk) /Rect [60 60 140 140] /F 4 /V /Yes /AS /Yes "
                + "/MK << /CA (4) /BC [0 0 0] >> /DA (/ZaDb 0 Tf 0 g) /AP << /N << /Yes 8 0 R /Off 9 0 R >> >> >>",
        ]
        var pdf = "%PDF-1.4\n"
        var offsets: [Int] = []
        for (index, object) in objects.enumerated() {
            offsets.append(pdf.utf8.count)
            pdf += "\(index + 1) 0 obj\n\(object)\nendobj\n"
        }
        let xref = pdf.utf8.count
        pdf += "xref\n0 \(objects.count + 1)\n0000000000 65535 f \n"
        for offset in offsets {
            pdf += String(format: "%010d 00000 n \n", offset)
        }
        pdf += "trailer\n<< /Size \(objects.count + 1) /Root 1 0 R >>\nstartxref\n\(xref)\n%%EOF\n"
        return Data(pdf.utf8)
    }

    private static func stream(_ content: String, dictionary: String) -> String {
        "<< \(dictionary) /Length \(content.utf8.count) >>\nstream\n\(content)\nendstream"
    }
}
