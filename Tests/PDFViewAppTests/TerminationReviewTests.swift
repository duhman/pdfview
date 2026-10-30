import Testing
@testable import PDFViewApp

@MainActor
private final class FakeWindow: QuitReviewable {
    let hasUnsavedWork: Bool
    let answer: Bool
    var reviewed = 0

    init(unsaved: Bool, answer: Bool = true) {
        hasUnsavedWork = unsaved
        self.answer = answer
    }

    func reviewBeforeQuitting(then done: @escaping (Bool) -> Void) {
        reviewed += 1
        done(answer)
    }
}

@MainActor
private func decide(_ windows: [FakeWindow], choice: QuitReviewChoice) -> (proceed: Bool?, asked: [Int]) {
    var asked: [Int] = []
    var proceed: Bool?
    TerminationReview.run(
        windows,
        choose: { count in
            asked.append(count)
            return choice
        },
        completion: { proceed = $0 }
    )
    return (proceed, asked)
}

@MainActor
@Test func quitsAtOnceWhenNothingIsUnsaved() {
    let windows = [FakeWindow(unsaved: false)]
    let result = decide(windows, choice: .cancel)
    #expect(result.proceed == true)
    #expect(result.asked.isEmpty)
    #expect(windows[0].reviewed == 0)
}

@MainActor
@Test func singleUnsavedWindowIsReviewedWithoutTheSummaryAlert() {
    let windows = [FakeWindow(unsaved: false), FakeWindow(unsaved: true, answer: false)]
    let result = decide(windows, choice: .discardAll)
    #expect(result.asked.isEmpty)
    #expect(windows[1].reviewed == 1)
    #expect(result.proceed == false)
}

@MainActor
@Test func summaryChoicesCancelDiscardOrReviewEachWindowInTurn() {
    let cancelled = [FakeWindow(unsaved: true), FakeWindow(unsaved: true)]
    #expect(decide(cancelled, choice: .cancel) == (false, [2]))
    #expect(cancelled.map(\.reviewed) == [0, 0])

    let discarded = [FakeWindow(unsaved: true), FakeWindow(unsaved: true)]
    #expect(decide(discarded, choice: .discardAll).proceed == true)
    #expect(discarded.map(\.reviewed) == [0, 0])

    let reviewed = [FakeWindow(unsaved: true), FakeWindow(unsaved: true, answer: false), FakeWindow(unsaved: true)]
    #expect(decide(reviewed, choice: .review).proceed == false)
    // Cancelling the second window's prompt stops the review and the quit.
    #expect(reviewed.map(\.reviewed) == [1, 1, 0])
}

@Test func summaryAlertCountsDocuments() {
    #expect(
        TerminationReview.summaryMessage(count: 3)
            == "You have 3 documents with unsaved signatures or form entries. "
            + "Do you want to review them before quitting?"
    )
}
