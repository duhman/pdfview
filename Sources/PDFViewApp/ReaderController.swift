import AppKit
import Observation
@preconcurrency import Quartz

@MainActor
@Observable
final class ReaderController: NSObject {
    var sidebarVisible = false
    var showGoToPage = false
    var displayMode: ReaderDisplayMode = .singleContinuous {
        didSet { view?.displayMode = displayMode.pdfKitMode }
    }

    var displaysAsBook = false {
        didSet { view?.displaysAsBook = displaysAsBook }
    }

    private(set) var pageIndex: Int?
    private(set) var pageCount = 0
    private(set) var pageLabel: String?
    private(set) var outline: [ReaderOutlineNode] = []
    private(set) var currentOutlineID: ObjectIdentifier?
    private(set) var printDisabledReason: String?
    private(set) weak var view: PDFView?
    let find = FindController()

    private(set) weak var observedClipView: NSClipView?
    private var outlineByPage: [Int: ObjectIdentifier] = [:]
    private var resolvedOutlinePages: Set<Int> = []
    private weak var attachedDocument: PDFDocument?
    private var fileURL: URL?
    private var restored = false
    private var isRestoring = false
    private var persistenceTask: Task<Void, Never>?
    private let defaults: UserDefaults
    private static let prefs = "reader.positions.v1"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        super.init()
    }

    var pageIndicator: String {
        ReaderLogic.pageIndicator(index: pageIndex, count: pageCount, label: pageLabel)
    }

    var canRead: Bool {
        pageCount > 0 && attachedDocument?.isLocked == false
    }

    var canGoNext: Bool {
        canRead && (pageIndex ?? 0) < pageCount - 1
    }

    var canGoPrevious: Bool {
        canRead && (pageIndex ?? 0) > 0
    }

    var canPrint: Bool {
        canRead && printDisabledReason == nil
    }

    func attach(to view: PDFView, fileURL: URL?) {
        guard self.view !== view || attachedDocument !== view.document || self.fileURL != fileURL else { return }
        detach()
        self.view = view
        attachedDocument = view.document
        self.fileURL = fileURL
        restored = false
        view.displayMode = displayMode.pdfKitMode
        view.displaysAsBook = displaysAsBook
        find.attach(to: view)
        let center = NotificationCenter.default
        for name in [Notification.Name.PDFViewPageChanged, .PDFViewScaleChanged] {
            center.addObserver(self, selector: #selector(viewChanged), name: name, object: view)
        }
        center.addObserver(self, selector: #selector(unlocked), name: .PDFDocumentDidUnlock, object: view.document)
        observeScrollView()
        DispatchQueue.main.async { [weak self] in
            self?.observeScrollView()
            self?.restoreIfNeeded()
            self?.refresh()
        }
    }

    func detach() {
        persistenceTask?.cancel()
        persist()
        find.close()
        let names: [Notification.Name] = [
            .PDFViewPageChanged, .PDFViewScaleChanged, .PDFDocumentDidUnlock, NSView.boundsDidChangeNotification,
        ]
        for name in names {
            NotificationCenter.default.removeObserver(self, name: name, object: nil)
        }
        observedClipView = nil
        outlineByPage.removeAll()
        resolvedOutlinePages.removeAll()
        view = nil
        attachedDocument = nil
    }

    @objc private func unlocked() {
        restoreIfNeeded()
        refresh()
    }

    @objc private func viewChanged() {
        DispatchQueue.main.async { [weak self] in
            self?.refreshPage()
            self?.schedulePersistence()
        }
    }

    @objc private func scrolled(_ notification: Notification) {
        guard let clip = notification.object as? NSClipView, clip === observedClipView else { return }
        schedulePersistence()
    }

    func refresh() {
        guard let document = attachedDocument else { return }
        pageCount = document.pageCount
        outline = ReaderOutlineNode.children(of: document.outlineRoot) ?? []
        outlineByPage.removeAll()
        resolvedOutlinePages.removeAll()
        printDisabledReason = document.isLocked ? "Unlock this PDF to print." :
            (document.allowsPrinting ? nil : "Printing is not allowed by this PDF’s permissions.")
        refreshPage()
    }

    private func refreshPage() {
        guard let document = attachedDocument, let page = view?.currentPage else { return }
        let index = document.index(for: page)
        pageIndex = index == NSNotFound ? nil : index
        pageLabel = page.label
        if resolvedOutlinePages.insert(index).inserted {
            outlineByPage[index] = page.selection(for: page.bounds(for: .cropBox))
                .flatMap { document.outlineItem(for: $0) }
                .map(ObjectIdentifier.init)
        }
        currentOutlineID = outlineByPage[index]
    }

    private func observeScrollView() {
        guard let clip = view?.documentView?.enclosingScrollView?.contentView,
              clip !== observedClipView else { return }
        if let observedClipView {
            NotificationCenter.default.removeObserver(
                self, name: NSView.boundsDidChangeNotification, object: observedClipView
            )
        }
        observedClipView = clip
        clip.postsBoundsChangedNotifications = true
        NotificationCenter.default.addObserver(
            self, selector: #selector(scrolled(_:)), name: NSView.boundsDidChangeNotification, object: clip
        )
    }

    /// One cancellable annotation walk; callers can collect editable widgets alongside signature fields.
    static func scanSignatureFields(
        in document: PDFDocument,
        batchSize: Int = 16,
        batch: ([SignatureField]) -> Void = { _ in },
        visitPage: (PDFPage) -> Void = { _ in }
    ) async throws -> [SignatureField] {
        guard !document.isLocked else { return [] }
        var fields: [SignatureField] = []
        let stride = max(1, batchSize)
        for start in Swift.stride(from: 0, to: document.pageCount, by: stride) {
            try Task.checkCancellation()
            var found: [SignatureField] = []
            for index in start ..< min(start + stride, document.pageCount) {
                guard let page = document.page(at: index) else { continue }
                visitPage(page)
                found += page.annotations.filter(SigningFlowLogic.isSignatureField).map {
                    SignatureField(pageIndex: index, bounds: $0.bounds, name: $0.fieldName)
                }
            }
            fields += found
            batch(found)
            await Task.yield()
        }
        try Task.checkCancellation()
        return fields
    }

    func go(to index: Int) {
        guard let page = attachedDocument?.page(at: index) else { return }
        view?.go(to: page)
    }

    func follow(_ item: PDFOutline) {
        if let action = item.action {
            view?.perform(action)
        } else if let destination = item.destination {
            view?.go(to: destination)
        }
    }

    private func restoreIfNeeded() {
        guard !restored, let view, let document = attachedDocument, !document.isLocked else { return }
        restored = true
        isRestoring = true
        defer { isRestoring = false }
        guard let fileURL else { return }
        var store = ReadingPositionStore(data: defaults.data(forKey: Self.prefs))
        guard let position = store.position(for: fileURL, pageCount: document.pageCount),
              let page = document.page(at: position.pageIndex) else { return }
        view.layoutSubtreeIfNeeded()
        view.autoScales = position.scale == nil
        if let scale = position.scale {
            view.scaleFactor = ZoomState.clampedScale(scale)
        }
        view.go(to: PDFDestination(page: page, at: CGPoint(x: position.x, y: position.y)))
    }

    private func schedulePersistence() {
        guard restored, !isRestoring else { return }
        persistenceTask?.cancel()
        persistenceTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(250))
            guard !Task.isCancelled else { return }
            self?.persist()
        }
    }

    func persist() {
        guard restored, !isRestoring, let fileURL, let view, let document = attachedDocument,
              !document.isLocked, let destination = view.currentDestination, let page = destination.page else { return }
        let position = ReadingPosition(
            pageIndex: document.index(for: page),
            x: destination.point.x,
            y: destination.point.y,
            scale: view.autoScales ? nil : view.scaleFactor
        )
        guard position.pageIndex != NSNotFound else { return }
        var store = ReadingPositionStore(data: defaults.data(forKey: Self.prefs))
        store.save(position, for: fileURL)
        if let data = try? store.encoded() {
            defaults.set(data, forKey: Self.prefs)
        }
    }
}

struct ReaderOutlineNode: Identifiable {
    let item: PDFOutline
    var id: ObjectIdentifier {
        ObjectIdentifier(item)
    }

    let children: [ReaderOutlineNode]?

    static func children(of item: PDFOutline?) -> [ReaderOutlineNode]? {
        guard let item, item.numberOfChildren > 0 else { return nil }
        return (0 ..< item.numberOfChildren).compactMap { index in
            item.child(at: index).map { ReaderOutlineNode(item: $0, children: children(of: $0)) }
        }
    }
}
