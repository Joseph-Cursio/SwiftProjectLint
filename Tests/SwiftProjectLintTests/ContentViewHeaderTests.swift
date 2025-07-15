import Testing
import SwiftUI
import ViewInspector

@testable import SwiftProjectLint

@Suite
@MainActor
struct ContentViewHeaderTests {
    @Test
    func testHeaderStructureAndContent() throws {
        let view = ContentViewHeader()
        let inspected = try view.inspect()
        let vStack = try inspected.vStack()
        // Check for Image (just presence)
        _ = try vStack.image(0)
        // Check for main title
        let titleText = try vStack.text(1)
        #expect(try titleText.string() == "Swift Project Linter")
        // Check for description
        let descText = try vStack.text(2)
        #expect(try descText.string() == "Detect cross-file issues and architectural problems")
    }
} 