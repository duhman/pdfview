import AppKit
import ImageIO
@preconcurrency import Quartz

/// Only capture touches the live PDF on the main actor. A private copy belongs exclusively to the worker.
enum SignedPDFExporter {
    private typealias ExportError = PDFViewerDocument.ExportError
    private typealias Placement = PDFViewerDocument.SignaturePlacement

    private struct Stamp {
        let bounds: CGRect
        let image: CGImage
    }

    private struct PreparedPDF {
        let document: PDFDocument
        let rendered: PDFDocument
        let pages: [PDFPage]
    }

    /// PDFKit does not declare Sendable. This private box transfers exclusive ownership of a deep
    /// copy to one worker; neither the live document nor any of its pages are stored here.
    private struct Snapshot: @unchecked Sendable {
        let document: PDFDocument
        let pages: [PDFPage]
        let state: ExportedState
    }

    /// A user password must never become an owner credential for a restricted copy.
    private struct Protection: Sendable {
        let password: String
        let ownerPassword: String
        let permissions: UInt
        let isOwner: Bool

        init(source: PDFDocument, password: String) {
            self.password = password
            permissions = source.accessPermissions.rawValue
            isOwner = source.permissionsStatus == .owner
            ownerPassword = isOwner ? password : UUID().uuidString
        }

        var options: [PDFDocumentWriteOption: Any] {
            [
                .userPasswordOption: password,
                .ownerPasswordOption: ownerPassword,
                .accessPermissionsOption: NSNumber(value: permissions),
            ]
        }

        func validate(_ document: PDFDocument) throws {
            guard document.accessPermissions.rawValue == permissions,
                  (document.permissionsStatus == .owner) == isOwner
            else {
                throw ExportError.cannotPreserveAccessPermissions
            }
        }
    }

    @MainActor
    @discardableResult
    static func writeAsync(
        _ source: PDFDocument,
        placements: [PDFViewerDocument.SignaturePlacement],
        to destination: URL,
        password: String? = nil,
        originalURL: URL? = nil,
        progress: @escaping @MainActor @Sendable (ExportProgress) -> Void
    ) async throws -> ExportedState {
        let originalURL = originalURL ?? source.documentURL
        try SignedCopyOperation.validateDestination(destination, originalURL: originalURL)
        guard !source.isLocked else { throw ExportError.documentLocked }
        try Task.checkCancellation()
        // No suspension between baseline capture and copying the live PDF.
        guard let values = FormScan.capture(source)?.values() else { throw ExportError.cannotEncodeDocumentData }
        let protection = password.map { Protection(source: source, password: $0) }
        let copy = try snapshot(of: source)
        let snapshot = try Snapshot(
            document: copy, pages: pages(in: copy), state: ExportedState(placements: placements, formValues: values)
        )
        let worker = Task.detached(priority: .userInitiated) {
            try await writeSnapshot(
                snapshot,
                to: destination,
                protection: protection,
                originalURL: originalURL,
                progress: progress
            )
        }
        return try await withTaskCancellationHandler {
            try await worker.value
        } onCancel: {
            worker.cancel()
        }
    }

    private static func writeSnapshot(
        _ snapshot: Snapshot,
        to destination: URL,
        protection: Protection?,
        originalURL: URL?,
        progress: @MainActor @Sendable (ExportProgress) -> Void
    ) async throws -> ExportedState {
        let source = snapshot.document
        defer { withExtendedLifetime(snapshot) {} }
        do {
            try Task.checkCancellation()
            let stamps = try decode(snapshot.state.placements, pageCount: source.pageCount)
            let manager = FileManager.default
            let staging = try manager.url(
                for: .itemReplacementDirectory, in: .userDomainMask, appropriateFor: destination, create: true
            )
            defer { try? manager.removeItem(at: staging) }
            let rendered = staging.appendingPathComponent("rendered.pdf")
            let completed = staging.appendingPathComponent("completed.pdf")
            try await renderAsync(snapshot.pages, stamps: stamps, to: rendered, progress: progress)
            try await finalizeAsync(rendered, from: source, to: completed, protection: protection, progress: progress)
            try SignedCopyOperation.validateDestination(destination, originalURL: originalURL)
            try Task.checkCancellation()
            if manager.fileExists(atPath: destination.path) {
                _ = try manager.replaceItemAt(destination, withItemAt: completed)
            } else {
                try manager.moveItem(at: completed, to: destination)
            }
            return snapshot.state
        } catch let error as ExportError {
            throw error
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw ExportError.writeFailed(description: error.localizedDescription)
        }
    }

    private static func renderAsync(
        _ pages: [PDFPage], stamps: [Int: [Stamp]], to url: URL, progress: @MainActor @Sendable (ExportProgress) -> Void
    ) async throws {
        guard let context = CGContext(url as CFURL, mediaBox: nil, nil) else {
            throw ExportError.cannotCreatePDFContext
        }
        defer { context.closePDF() }
        await progress(ExportProgress(completedPages: 0, totalPages: pages.count))
        await Task.yield()
        for (index, page) in pages.enumerated() {
            try Task.checkCancellation()
            renderPage(page, stamps: stamps[index] ?? [], in: context)
            await progress(ExportProgress(completedPages: index + 1, totalPages: pages.count))
            await Task.yield()
        }
    }

    private static func renderPage(_ page: PDFPage, stamps: [Stamp], in context: CGContext) {
        autoreleasepool {
            let media = page.bounds(for: .mediaBox)
            context.beginPDFPage([
                kCGPDFContextMediaBox as String: boxData(media),
                kCGPDFContextCropBox as String: boxData(page.bounds(for: .cropBox)),
            ] as CFDictionary)
            defer { context.endPDFPage() }
            draw(page, media: media, in: context)
            for stamp in stamps {
                context.draw(stamp.image, in: stamp.bounds)
            }
        }
    }

    private static func pages(in document: PDFDocument) throws -> [PDFPage] {
        try (0 ..< document.pageCount).map { index in
            guard let page = document.page(at: index) else { throw ExportError.cannotReadPage(index: index) }
            return page
        }
    }

    private static func structuredDocument(_ rendered: URL, from source: PDFDocument) throws -> PreparedPDF {
        let renderedDocument = try validatedDocument(at: rendered, pageCount: source.pageCount)
        let outputPages = try pages(in: renderedDocument)
        let output = PDFDocument()
        // A fresh page tree makes PDFKit resolve GoTo references and serialize a rebuilt outline.
        // Writing the rendered document in place can leave symbolic /##page destinations in the file.
        for (index, page) in outputPages.enumerated() {
            output.insert(page, at: index)
        }
        try restoreStructure(from: source, to: output)
        return PreparedPDF(document: output, rendered: renderedDocument, pages: outputPages)
    }

    private static func snapshot(of source: PDFDocument) throws -> PDFDocument {
        let originalPages = try pages(in: source)
        defer { withExtendedLifetime(originalPages) {} }
        guard let copy = source.copy() as? PDFDocument, !copy.isLocked else {
            throw ExportError.cannotEncodeDocumentData
        }
        // NSCopying freezes page/annotation state, including unlocked encrypted pages, but loses GoTo targets.
        for page in try pages(in: copy) {
            for link in page.annotations where link.type == "Link" {
                page.removeAnnotation(link)
            }
        }
        try restoreStructure(from: source, to: copy)
        return copy
    }

    private static func geometry(of pages: [PDFPage]) -> [PDFExportPageGeometry] {
        pages.map { PDFExportPageGeometry(media: $0.bounds(for: .mediaBox), crop: $0.bounds(for: .cropBox)) }
    }

    private static func write(_ output: PreparedPDF, to url: URL, protection: Protection?) throws {
        // PDFKit destinations hold weak page references; retain every page through serialization.
        defer { withExtendedLifetime(output) {} }
        let options = protection?.options ?? [:]
        guard output.document.write(to: url, withOptions: options) else { throw ExportError.cannotEncodeDocumentData }
    }

    private static func finalizeAsync(
        _ rendered: URL,
        from source: PDFDocument,
        to completed: URL,
        protection: Protection?,
        progress: @MainActor @Sendable (ExportProgress) -> Void
    ) async throws {
        let boxes = try geometry(of: pages(in: source))
        let count = source.pageCount
        let output = try structuredDocument(rendered, from: source)
        await progress(ExportProgress(completedPages: count, totalPages: count, stage: .writing))
        await Task.yield()
        try Task.checkCancellation()
        try write(output, to: completed, protection: protection)
        await progress(ExportProgress(completedPages: count, totalPages: count, stage: .restoringGeometry))
        await Task.yield()
        try Task.checkCancellation()
        try PDFExportGeometry.restore(at: completed, pages: boxes)
        await progress(ExportProgress(completedPages: count, totalPages: count, stage: .validating))
        await Task.yield()
        try Task.checkCancellation()
        let validated = try validatedDocument(at: completed, pageCount: count, password: protection?.password)
        try protection?.validate(validated)
        await Task.yield()
        try Task.checkCancellation()
    }

    private static func decode(_ placements: [Placement], pageCount: Int) throws -> [Int: [Stamp]] {
        var images: [Data: CGImage] = [:]
        var stamps: [Int: [Stamp]] = [:]
        for placement in placements {
            guard (0 ..< pageCount).contains(placement.pageIndex) else {
                throw ExportError.invalidPlacementPage(index: placement.pageIndex)
            }
            let image: CGImage
            if let cached = images[placement.signaturePNGData] {
                image = cached
            } else {
                guard let source = CGImageSourceCreateWithData(placement.signaturePNGData as CFData, nil),
                      let decoded = CGImageSourceCreateImageAtIndex(source, 0, nil)
                else { throw ExportError.cannotDecodeSignature(id: placement.id) }
                image = decoded
                images[placement.signaturePNGData] = image
            }
            stamps[placement.pageIndex, default: []].append(Stamp(bounds: placement.bounds, image: image))
        }
        return stamps
    }

    private static func draw(_ page: PDFPage, media: CGRect, in context: CGContext) {
        let rotation = page.rotation
        let displaysAnnotations = page.displaysAnnotations
        page.rotation = 0
        page.displaysAnnotations = true
        context.saveGState()
        defer {
            context.restoreGState()
            page.rotation = rotation
            page.displaysAnnotations = displaysAnnotations
        }
        // PDFKit normalizes the media-box origin; undo that translation to keep PDF page coordinates.
        context.translateBy(x: media.minX, y: media.minY)
        page.draw(with: .mediaBox, to: context)
    }

    private static func boxData(_ box: CGRect) -> Data {
        var box = box
        return Data(bytes: &box, count: MemoryLayout<CGRect>.size)
    }

    private static func validatedDocument(at url: URL, pageCount: Int, password: String? = nil) throws -> PDFDocument {
        guard let document = PDFDocument(url: url) else { throw ExportError.invalidExportedDocument }
        if let password {
            guard document.isEncrypted, document.unlock(withPassword: password) else {
                throw ExportError.invalidExportedDocument
            }
        }
        guard !document.isLocked, document.pageCount == pageCount else {
            throw ExportError.invalidExportedDocument
        }
        for index in 0 ..< pageCount where document.page(at: index)?.pageRef == nil {
            throw ExportError.invalidExportedDocument
        }
        return document
    }
}

extension SignedPDFExporter {
    private static func restoreStructure(from source: PDFDocument, to output: PDFDocument) throws {
        for index in 0 ..< source.pageCount {
            guard let page = source.page(at: index), let result = output.page(at: index) else {
                throw ExportError.cannotReadPage(index: index)
            }
            result.rotation = page.rotation
            result.setBounds(page.bounds(for: .mediaBox), for: .mediaBox)
            result.setBounds(page.bounds(for: .cropBox), for: .cropBox)
            for link in page.annotations where link.type == "Link" {
                // PDFAnnotation.copy() can omit newly created links when PDFKit serializes them.
                let copy = PDFAnnotation(bounds: link.bounds, forType: .link, withProperties: link.annotationKeyValues)
                if let action = link.action as? PDFActionGoTo {
                    copy.action = try PDFActionGoTo(destination: mapped(action.destination, from: source, to: output))
                } else if let destination = link.destination {
                    copy.destination = try mapped(destination, from: source, to: output)
                }
                result.addAnnotation(copy)
            }
        }
        if let root = source.outlineRoot {
            output.outlineRoot = try copyOutline(root, from: source, to: output)
        }
        output.documentAttributes = source.documentAttributes
    }

    private static func mapped(
        _ destination: PDFDestination, from source: PDFDocument, to output: PDFDocument
    ) throws -> PDFDestination {
        guard let page = destination.page,
              let result = output.page(at: source.index(for: page))
        else { throw ExportError.cannotPreserveNavigation }
        let copy = PDFDestination(page: result, at: destination.point)
        copy.zoom = destination.zoom
        return copy
    }

    private static func copyOutline(
        _ outline: PDFOutline, from source: PDFDocument, to output: PDFDocument
    ) throws -> PDFOutline {
        let copy = PDFOutline()
        copy.label = outline.label
        if let action = outline.action as? PDFActionGoTo {
            copy.action = try PDFActionGoTo(destination: mapped(action.destination, from: source, to: output))
        } else if let destination = outline.destination {
            copy.destination = try mapped(destination, from: source, to: output)
        } else {
            copy.action = outline.action?.copy() as? PDFAction
        }
        for index in 0 ..< outline.numberOfChildren {
            guard let child = outline.child(at: index) else { throw ExportError.cannotPreserveNavigation }
            try copy.insertChild(copyOutline(child, from: source, to: output), at: index)
        }
        copy.isOpen = outline.isOpen
        return copy
    }
}

/// Repairs only our freshly generated PDFKit file. PDFKit's full writer normalizes media origins;
/// an incremental update restores the boxes and page-space content without rewriting image/font streams.
struct PDFExportPageGeometry: Sendable {
    let media: CGRect
    let crop: CGRect
}

struct PDFExportGeometry {
    private typealias ExportError = PDFViewerDocument.ExportError

    let data: Data
    let offsets: [Int]
    let limits: [Int: Int]
    let previousXref: Int
    let trailer: String

    init(url: URL) throws {
        data = try Data(contentsOf: url, options: .mappedIfSafe)
        guard let tail = String(bytes: data.suffix(1024), encoding: .isoLatin1) else {
            throw ExportError.cannotPreservePageGeometry
        }
        previousXref = try Self.integer("startxref\\s+(\\d+)\\s+%%EOF\\s*$", in: tail)
        guard (0 ..< data.count).contains(previousXref),
              let table = String(data: data[previousXref...], encoding: .ascii)
        else { throw ExportError.cannotPreservePageGeometry }
        let lines = table.components(separatedBy: .newlines)
        guard lines.count > 2, lines[0] == "xref" else { throw ExportError.cannotPreservePageGeometry }
        let header = lines[1].split(separator: " ")
        guard header.count == 2, header[0] == "0", let count = Int(header[1]), count >= 0,
              count < lines.count - 2
        else {
            throw ExportError.cannotPreservePageGeometry
        }
        offsets = try lines[2 ..< count + 2].map { line in
            let fields = line.split(separator: " ")
            guard fields.count == 3, let offset = Int(fields[0]), fields[1] == "00000" || fields[2] == "f" else {
                throw ExportError.cannotPreservePageGeometry
            }
            return fields[2] == "n" ? offset : 0
        }
        let xrefOffset = previousXref
        guard offsets.allSatisfy({ $0 == 0 || (0 ..< xrefOffset).contains($0) }),
              Set(offsets.filter { $0 > 0 }).count == offsets.filter({ $0 > 0 }).count
        else { throw ExportError.cannotPreservePageGeometry }
        let sorted = offsets.filter { $0 > 0 }.sorted() + [previousXref]
        limits = Dictionary(uniqueKeysWithValues: zip(sorted, sorted.dropFirst()))
        trailer = try Self.capture("trailer\\s*(<<[\\s\\S]*>>)\\s*startxref", in: table)
        guard try Self.integer("/Size\\s+(\\d+)", in: trailer) == count else {
            throw ExportError.cannotPreservePageGeometry
        }
    }

    static func restore(at url: URL, pages: [PDFExportPageGeometry]) throws {
        guard pages.contains(where: { $0.media.origin != .zero }) else { return }
        let file = try PDFExportGeometry(url: url)
        // Adding plaintext content streams to encrypted output would corrupt its appearance.
        guard !file.trailer.contains("/Encrypt") else { throw ExportError.cannotPreservePageGeometry }
        let root = try integer("/Root\\s+(\\d+)\\s+0\\s+R", in: file.trailer)
        let pageRoot = try integer("/Pages\\s+(\\d+)\\s+0\\s+R", in: file.body(root))
        var visited: Set<Int> = []
        let pageIDs = try file.pageIDs(pageRoot, visited: &visited)
        guard pageIDs.count == pages.count else { throw ExportError.cannotPreservePageGeometry }
        var updates: [Int: String] = [:]
        var nextID = file.offsets.count
        for (index, page) in pages.enumerated() {
            let media = page.media
            guard media.origin != .zero else { continue }
            let pageID = pageIDs[index]
            let body = try file.body(pageID)
            let contents = try capture("/Contents\\s*(\\[[^\\]]*\\]|\\d+\\s+0\\s+R)", in: body)
            let references = contents.hasPrefix("[") ? String(contents.dropFirst().dropLast()) : contents
            updates[nextID] = stream("q\n1 0 0 1 \(media.minX) \(media.minY) cm\n")
            updates[nextID + 1] = stream("Q\n")
            var corrected = set("Contents", to: "[\(nextID) 0 R \(references) \(nextID + 1) 0 R]", in: body)
            corrected = set("MediaBox", to: rect(media), in: corrected)
            updates[pageID] = set("CropBox", to: rect(page.crop), in: corrected)
            nextID += 2
            try file.restoreLinkRects(in: body, origin: media.origin, updates: &updates)
        }
        try file.append(updates, size: nextID, to: url)
    }

    private func body(_ object: Int) throws -> String {
        guard offsets.indices.contains(object), let limit = limits[offsets[object]],
              let text = String(data: data[offsets[object] ..< limit], encoding: .isoLatin1)
        else { throw ExportError.cannotPreservePageGeometry }
        return try Self.capture("^\\d+\\s+0\\s+obj\\s*([\\s\\S]*?)\\s*endobj\\s*$", in: text)
    }

    private func pageIDs(_ object: Int, visited: inout Set<Int>) throws -> [Int] {
        guard visited.insert(object).inserted else { throw ExportError.cannotPreservePageGeometry }
        let body = try body(object)
        if body.range(of: "/Type\\s*/Page\\b", options: .regularExpression) != nil {
            return [object]
        }
        let kids = try array("Kids", in: body)
        return try references(in: kids).flatMap { try pageIDs($0, visited: &visited) }
    }

    private func array(_ key: String, in body: String) throws -> String {
        let value = try Self.capture("/\(key)\\s*(\\[[^\\]]*\\]|\\d+\\s+0\\s+R)", in: body)
        if value.hasPrefix("[") {
            return value
        }
        return try self.body(Self.integer("(\\d+)\\s+0\\s+R", in: value))
    }

    private func references(in text: String) throws -> [Int] {
        let expression = try NSRegularExpression(pattern: "(\\d+)\\s+0\\s+R")
        return try expression.matches(in: text, range: NSRange(text.startIndex..., in: text)).map { match in
            guard let range = Range(match.range(at: 1), in: text), let number = Int(text[range]) else {
                throw ExportError.cannotPreservePageGeometry
            }
            return number
        }
    }

    private func restoreLinkRects(in page: String, origin: CGPoint, updates: inout [Int: String]) throws {
        guard page.contains("/Annots") else { return }
        for object in try references(in: array("Annots", in: page)) {
            let body = try body(object)
            let coordinates = try Self.capture("/Rect\\s*\\[([^\\]]*)\\]", in: body, ignoringStrings: true)
            let values = coordinates.split(whereSeparator: \.isWhitespace).compactMap { Double($0) }
            guard values.count == 4 else { throw ExportError.cannotPreservePageGeometry }
            let bounds = CGRect(
                x: values[0] + origin.x,
                y: values[1] + origin.y,
                width: values[2] - values[0],
                height: values[3] - values[1]
            )
            updates[object] = Self.set("Rect", to: Self.rect(bounds), in: body)
        }
    }

    private func append(_ updates: [Int: String], size: Int, to url: URL) throws {
        var suffix = Data("\n".utf8)
        var xref: [Int: Int] = [:]
        for object in updates.keys.sorted() {
            xref[object] = data.count + suffix.count
            let text = "\(object) 0 obj\n\(updates[object, default: ""])\nendobj\n"
            guard let encoded = text.data(using: .isoLatin1) else { throw ExportError.cannotPreservePageGeometry }
            suffix.append(encoded)
        }
        let position = data.count + suffix.count
        suffix.append(Data("xref\n".utf8))
        for object in xref.keys.sorted() {
            let entry = String(format: "%010lld 00000 n \n", Int64(xref[object, default: 0]))
            suffix.append(Data("\(object) 1\n\(entry)".utf8))
        }
        let trailer = trailer.replacingOccurrences(
            of: "/Size\\s+\\d+",
            with: "/Size \(size)",
            options: .regularExpression
        )
        let dictionary = String(trailer.dropLast(2)) + "/Prev \(previousXref) >>"
        suffix.append(Data("trailer\n\(dictionary)\nstartxref\n\(position)\n%%EOF\n".utf8))
        let handle = try FileHandle(forWritingTo: url)
        defer { try? handle.close() }
        try handle.seekToEnd()
        try handle.write(contentsOf: suffix)
    }

    private static func capture(_ pattern: String, in text: String, ignoringStrings: Bool = false) throws -> String {
        let expression = try NSRegularExpression(pattern: pattern)
        let search = ignoringStrings ? maskStrings(in: text) : text
        guard let match = expression.firstMatch(in: search, range: NSRange(search.startIndex..., in: search)),
              let range = Range(match.range(at: 1), in: text)
        else { throw ExportError.cannotPreservePageGeometry }
        return String(text[range])
    }

    private static func integer(_ pattern: String, in text: String) throws -> Int {
        guard let value = try Int(capture(pattern, in: text)) else { throw ExportError.cannotPreservePageGeometry }
        return value
    }

    private static func set(_ key: String, to value: String, in body: String) -> String {
        let pattern = "/\(key)\\s*(?:\\[[^\\]]*\\]|\\d+\\s+0\\s+R)"
        let search = maskStrings(in: body)
        guard let match = search.range(of: pattern, options: .regularExpression),
              let range = Range(NSRange(match, in: search), in: body)
        else { return String(body.dropLast(2)) + "/\(key) \(value) >>" }
        return body.replacingCharacters(in: range, with: "/\(key) \(value)")
    }

    private static func maskStrings(in text: String) -> String {
        var units = Array(text.utf16)
        var depth = 0
        var escaped = false
        for index in units.indices {
            let unit = units[index]
            if depth > 0 {
                units[index] = 32
                if escaped {
                    escaped = false
                } else if unit == 92 {
                    escaped = true
                } else if unit == 40 {
                    depth += 1
                } else if unit == 41 {
                    depth -= 1
                }
            } else if unit == 40 {
                depth = 1
                units[index] = 32
            }
        }
        return String(decoding: units, as: UTF16.self)
    }

    private static func rect(_ rect: CGRect) -> String {
        "[\(rect.minX) \(rect.minY) \(rect.maxX) \(rect.maxY)]"
    }

    private static func stream(_ commands: String) -> String {
        "<< /Length \(commands.utf8.count) >>\nstream\n\(commands)endstream"
    }
}

struct ExportProgress: Equatable, Sendable {
    enum Stage: Hashable, Sendable {
        case rendering, writing, restoringGeometry, validating
    }

    var completedPages: Int
    var totalPages: Int
    var stage: Stage = .rendering
    var fraction: Double {
        totalPages > 0 ? Double(completedPages) / Double(totalPages) : 0
    }

    var text: String {
        switch stage {
        case .rendering: "Saving signed copy… \(completedPages) of \(totalPages) pages"
        case .writing: "Writing signed copy…"
        case .restoringGeometry: "Preserving page geometry…"
        case .validating: "Checking signed copy…"
        }
    }
}
