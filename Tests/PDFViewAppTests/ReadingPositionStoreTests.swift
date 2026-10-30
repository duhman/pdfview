import Foundation
import Testing
@testable import PDFViewApp

struct ReadingPositionStoreTests {
    private let position = ReadingPosition(pageIndex: 3, x: 20, y: 80, scale: 1.5)

    @Test func persistsWithoutPathsAndSeparatesFiles() throws {
        let first = URL(fileURLWithPath: "/private/contract.pdf")
        let second = URL(fileURLWithPath: "/other/contract.pdf")
        var store = ReadingPositionStore()
        store.save(position, for: first)
        let data = try store.encoded()
        #expect(try !#require(String(data: data, encoding: .utf8)).contains("contract"))
        var reloaded = ReadingPositionStore(data: data)
        #expect(reloaded.position(for: first, pageCount: 5) == position)
        #expect(reloaded.position(for: second, pageCount: 5) == nil)
        #expect(reloaded.position(for: first, pageCount: 2) == nil)
    }

    @Test func evictsLeastRecentlyUsedEntryAt200() {
        var store = ReadingPositionStore()
        let urls = (0 ... 200).map { URL(fileURLWithPath: "/\($0).pdf") }
        for url in urls.prefix(200) {
            store.save(position, for: url)
        }
        _ = store.position(for: urls[0], pageCount: 10)
        store.save(position, for: urls[200])
        #expect(store.count == 200)
        #expect(store.position(for: urls[1], pageCount: 10) == nil)
        #expect(store.position(for: urls[0], pageCount: 10) == position)
    }

    @Test func ignoresCorruptAndInvalidPositions() {
        var store = ReadingPositionStore(data: Data("broken".utf8))
        let url = URL(fileURLWithPath: "/a.pdf")
        store.save(ReadingPosition(pageIndex: -1, x: 0, y: 0, scale: nil), for: url)
        #expect(store.isEmpty)
        store.save(ReadingPosition(pageIndex: 1, x: .nan, y: 0, scale: nil), for: url)
        #expect(store.isEmpty)
        store.save(ReadingPosition(pageIndex: 1, x: 0, y: 0, scale: nil), for: url)
        #expect(store.position(for: url, pageCount: 2)?.scale == nil)
    }
}
