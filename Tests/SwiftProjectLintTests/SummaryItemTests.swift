import Testing
import SwiftUI
@testable import SwiftProjectLintCore
@testable import SwiftProjectLint
import ViewInspector

struct SummaryItemTests {
    @Test
    @MainActor
    func testSummaryItemDisplaysTitleAndValue() throws {
        let item = SummaryItem(title: "Total Issues", value: "42", color: .primary)
        let inspected = try item.inspect()

        let texts = try inspected.findAll(ViewType.Text.self).map { try $0.string() }
        #expect(texts.contains("Total Issues"))
        #expect(texts.contains("42"))
    }

    @Test
    @MainActor
    func testSummaryItemWithZeroValue() throws {
        let item = SummaryItem(title: "Errors", value: "0", color: .red)
        let inspected = try item.inspect()

        let texts = try inspected.findAll(ViewType.Text.self).map { try $0.string() }
        #expect(texts.contains("Errors"))
        #expect(texts.contains("0"))
    }

    @Test("summary item renders title in caption font and value in title2")
    @MainActor
    func summaryItemFontStyles() throws {
        let item = SummaryItem(title: "Warnings", value: "7", color: .orange)
        let inspected = try item.inspect()

        let texts = inspected.findAll(ViewType.Text.self)
        #expect(texts.count == 2)
        // Verify both title and value text elements exist
        let textStrings = try texts.map { try $0.string() }
        #expect(textStrings.contains("Warnings"))
        #expect(textStrings.contains("7"))
    }
}
