import CryptoKit
import Foundation

struct ReadingPosition: Codable, Equatable {
    var pageIndex: Int
    var x: Double
    var y: Double
    /// Nil means Zoom to Fit.
    var scale: Double?

    var isValid: Bool {
        pageIndex >= 0 && x.isFinite && y.isFinite && (scale.map { $0.isFinite && $0 > 0 } ?? true)
    }
}

/// Value-only persistence with hashed path keys and a deterministic least-recently-used bound.
struct ReadingPositionStore: Codable {
    private struct Entry: Codable {
        var position: ReadingPosition
        var access: Int
    }

    private var entries: [String: Entry] = [:]
    private var clock = 0
    var isEmpty: Bool {
        entries.isEmpty
    }

    var count: Int {
        entries.count
    }

    init(data: Data? = nil) {
        if let data, let decoded = try? JSONDecoder().decode(Self.self, from: data) {
            self = decoded
            entries = entries.filter(\.value.position.isValid)
            trim()
        }
    }

    mutating func save(_ position: ReadingPosition, for url: URL) {
        guard position.isValid else { return }
        clock += 1
        entries[Self.key(url)] = Entry(position: position, access: clock)
        trim()
    }

    mutating func position(for url: URL, pageCount: Int) -> ReadingPosition? {
        let key = Self.key(url)
        guard var entry = entries[key], entry.position.pageIndex < pageCount else { return nil }
        clock += 1
        entry.access = clock
        entries[key] = entry
        return entry.position
    }

    func encoded() throws -> Data {
        try JSONEncoder().encode(self)
    }

    private static func key(_ url: URL) -> String {
        SHA256.hash(data: Data(url.standardizedFileURL.path.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    private mutating func trim() {
        while entries.count > 200 {
            guard let oldest = entries.min(by: { $0.value.access < $1.value.access })?.key else { return }
            entries[oldest] = nil
        }
    }
}
