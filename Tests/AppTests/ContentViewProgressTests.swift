import Testing
import SwiftUI
import ViewInspector

@testable import SwiftProjectLint

@Suite
@MainActor
struct ContentViewProgressTests {
    @Test
    func testProgressWhenAnalyzing() throws {
        let view = ContentViewProgress(isAnalyzing: true)
        let inspected = try view.inspect()
        let vStack = try inspected.vStack()
        // ProgressView
        _ = try vStack.find(ViewType.ProgressView.self)
        // Status text
        let statusText = try vStack.text(1)
        #expect(try statusText.string() == "Analyzing project...")
    }

    @Test
    func testProgressWhenNotAnalyzing() throws {
        let view = ContentViewProgress(isAnalyzing: false)
        // Should render nothing
        #expect((try? view.inspect().vStack()) == nil)
    }
} 
