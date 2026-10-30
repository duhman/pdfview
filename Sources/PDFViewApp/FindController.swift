import AppKit
import Observation
@preconcurrency import Quartz

@MainActor
@Observable
final class FindController {
    var isVisible = false
    var focusRequest = 0
    private(set) var state = FindState()
    private weak var view: PDFView?
    private var matches: [PDFSelection] = []
    private var observers: [NSObjectProtocol] = []
    private var searchTask: Task<Void, Never>?

    func attach(to view: PDFView) {
        self.view = view
    }

    func show() {
        isVisible = true
        focusRequest += 1
    }

    func search(_ query: String) {
        stop()
        let generation = state.begin(query)
        clearHighlights()
        guard !query.isEmpty, let document = view?.document, !document.isLocked else { return }
        // Let the cancelled PDFKit find drain before registering the next generation's observers.
        searchTask = Task { [weak self] in
            await Task.yield()
            guard !Task.isCancelled, let self, state.generation == generation else { return }
            observe(document, generation: generation)
            document.beginFindString(query, withOptions: .caseInsensitive)
        }
    }

    private func observe(_ document: PDFDocument, generation: Int) {
        let center = NotificationCenter.default
        let match = center.addObserver(
            forName: .PDFDocumentDidFindMatch,
            object: document,
            queue: .main
        ) { [weak self] notification in
            // Foundation guarantees this block runs on .main; its non-Sendable payload stays there.
            nonisolated(unsafe) let mainNotification = notification
            MainActor.assumeIsolated { self?.receive(mainNotification, generation: generation) }
        }
        let end = center.addObserver(
            forName: .PDFDocumentDidEndFind,
            object: document,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.state.finish(generation: generation) }
        }
        observers = [match, end]
    }

    private func receive(_ notification: Notification, generation: Int) {
        guard state.generation == generation,
              let selection = notification.userInfo?["PDFDocumentFoundSelection"] as? PDFSelection else { return }
        selection.color = .systemYellow.withAlphaComponent(0.5)
        matches.append(selection)
        state.receiveMatch(generation: generation)
        view?.highlightedSelections = matches
        if matches.count == 1 {
            selectCurrent()
        }
    }

    func advance(backwards: Bool = false) {
        state.advance(backwards: backwards)
        selectCurrent()
    }

    private func selectCurrent() {
        guard let index = state.currentIndex, matches.indices.contains(index) else { return }
        view?.setCurrentSelection(matches[index], animate: true)
        view?.go(to: matches[index])
    }

    func close() {
        stop()
        state.close()
        clearHighlights()
        isVisible = false
    }

    private func clearHighlights() {
        matches = []
        view?.highlightedSelections = nil
        view?.clearSelection()
    }

    private func stop() {
        searchTask?.cancel()
        for observer in observers {
            NotificationCenter.default.removeObserver(observer)
        }
        observers = []
        view?.document?.cancelFindString()
    }
}
