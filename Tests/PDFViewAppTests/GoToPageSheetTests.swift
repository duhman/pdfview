import Testing
@testable import PDFViewApp

@Test func goToPageExplainsInvalidInputInline() {
    #expect(GoToPageSheet.validationMessage(input: "", count: 5) == nil)
    #expect(GoToPageSheet.validationMessage(input: "3", count: 5) == nil)
    #expect(GoToPageSheet.validationMessage(input: "9", count: 5) == "There is no page 9. Enter a number from 1 to 5.")
    #expect(GoToPageSheet.validationMessage(input: "0", count: 5) == "There is no page 0. Enter a number from 1 to 5.")
    #expect(GoToPageSheet.validationMessage(input: "abc", count: 5) == "Enter a page number from 1 to 5.")
}
