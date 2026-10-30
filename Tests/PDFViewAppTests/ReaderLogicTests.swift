import Foundation
import Quartz
import Testing
@testable import PDFViewApp

struct ReaderLogicTests {
    @Test func pageIndicatorUsesLabelsOnlyWhenDifferent() {
        #expect(ReaderLogic.pageIndicator(index: 3, count: 120, label: "iv") == "iv (4 of 120)")
        #expect(ReaderLogic.pageIndicator(index: 3, count: 120, label: "4") == "4 of 120")
        #expect(ReaderLogic.pageIndicator(index: nil, count: 0, label: nil) == "0 of 0")
    }

    @Test func validatesPhysicalPageNumbers() {
        #expect(ReaderLogic.pageIndex(input: " 4 ", count: 5) == 3)
        for invalid in ["0", "6", "-1", "iv", "1.5", "", "999999999999999999999"] {
            #expect(ReaderLogic.pageIndex(input: invalid, count: 5) == nil)
        }
        #expect(ReaderLogic.pageIndex(input: "1", count: 0) == nil)
    }

    @Test func findRejectsStaleResultsAndWraps() {
        var state = FindState()
        let old = state.begin("old")
        let current = state.begin("new")
        state.receiveMatch(generation: old)
        #expect(state.isEmpty)
        state.receiveMatch(generation: current)
        state.receiveMatch(generation: current)
        #expect(state.matchText == "1 of 2")
        state.advance(backwards: false)
        #expect(state.matchText == "2 of 2")
        state.advance(backwards: false)
        #expect(state.currentIndex == 0)
        state.advance(backwards: true)
        #expect(state.currentIndex == 1)
        state.finish(generation: old)
        #expect(state.isSearching)
        state.finish(generation: current)
        #expect(!state.isSearching)
        state.close()
        #expect(state.isEmpty)
        #expect(state.query.isEmpty)
        #expect(!state.isSearching)
        state.advance(backwards: true)
        #expect(state.currentIndex == nil)
        #expect(state.matchText == "0 of 0")
        _ = state.begin("")
        #expect(!state.isSearching)
    }

    @Test func displayModesMapToPDFKit() {
        #expect(ReaderDisplayMode.single.pdfKitMode == .singlePage)
        #expect(ReaderDisplayMode.singleContinuous.pdfKitMode == .singlePageContinuous)
        #expect(ReaderDisplayMode.two.pdfKitMode == .twoUp)
        #expect(ReaderDisplayMode.twoContinuous.pdfKitMode == .twoUpContinuous)
        #expect(ReaderDisplayMode.two.supportsCover)
        #expect(!ReaderDisplayMode.singleContinuous.supportsCover)
    }
}
