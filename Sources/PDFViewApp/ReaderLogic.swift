import Foundation
import Quartz

enum ReaderLogic {
    static func pageIndicator(index: Int?, count: Int, label: String?) -> String {
        guard let index, (0 ..< count).contains(index) else { return "0 of \(count)" }
        let physical = "\(index + 1) of \(count)"
        guard let label, !label.isEmpty, label != String(index + 1) else { return physical }
        return "\(label) (\(physical))"
    }

    static func pageIndex(input: String, count: Int) -> Int? {
        guard let number = Int(input.trimmingCharacters(in: .whitespacesAndNewlines)),
              number > 0, number <= count else { return nil }
        return number - 1
    }
}

enum ReaderDisplayMode: String, CaseIterable, Identifiable {
    case single = "Single Page"
    case singleContinuous = "Single Page Continuous"
    case two = "Two Pages"
    case twoContinuous = "Two Pages Continuous"

    var id: String {
        rawValue
    }

    var supportsCover: Bool {
        self == .two || self == .twoContinuous
    }

    var pdfKitMode: PDFDisplayMode {
        switch self {
        case .single: .singlePage
        case .singleContinuous: .singlePageContinuous
        case .two: .twoUp
        case .twoContinuous: .twoUpContinuous
        }
    }
}

struct FindState {
    private(set) var query = ""
    private(set) var generation = 0
    private(set) var count = 0
    private(set) var currentIndex: Int?
    private(set) var isSearching = false

    var isEmpty: Bool {
        // The count is numeric state, rather than a collection.
        // swiftlint:disable:next empty_count
        count == 0
    }

    var matchText: String {
        "\(currentIndex.map { $0 + 1 } ?? 0) of \(count)"
    }

    mutating func begin(_ query: String) -> Int {
        generation += 1
        self.query = query
        count = 0
        currentIndex = nil
        isSearching = !query.isEmpty
        return generation
    }

    mutating func receiveMatch(generation: Int) {
        guard generation == self.generation, isSearching else { return }
        count += 1
        if currentIndex == nil {
            currentIndex = 0
        }
    }

    mutating func finish(generation: Int) {
        guard generation == self.generation else { return }
        isSearching = false
    }

    mutating func advance(backwards: Bool) {
        guard let currentIndex, !isEmpty else { return }
        self.currentIndex = (currentIndex + (backwards ? count - 1 : 1)) % count
    }

    mutating func close() {
        _ = begin("")
    }
}
