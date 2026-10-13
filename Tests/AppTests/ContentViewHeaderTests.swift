import SwiftUI
import Testing
import ViewInspector

@testable import App

@Suite
@MainActor
struct ContentViewHeaderTests {
    @Test
    func testHeaderStructureAndContent() throws {
        let view = ContentViewHeader()
        let inspected = try view.inspect()
        // The app icon is the header's only image
        _ = try inspected.find(ViewType.Image.self)
        #expect(try inspected.headerTitle() == "Swift Project Linter")
        #expect(try inspected.headerSubtitle() == "Detect cross-file issues and architectural problems")
    }
}
