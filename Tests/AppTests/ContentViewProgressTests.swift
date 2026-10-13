import SwiftUI
import Testing
import ViewInspector

@testable import App

@Suite
@MainActor
struct ContentViewProgressTests {
    @Test
    func testProgressWhenAnalyzing() throws {
        let view = ContentViewProgress(isAnalyzing: true)
        let inspected = try view.inspect()
        _ = try inspected.find(ViewType.ProgressView.self)
        #expect(try inspected.analysisStatus() == "Analyzing project...")
    }

    @Test
    func testProgressWhenNotAnalyzing() {
        let view = ContentViewProgress(isAnalyzing: false)
        // Should render nothing
        #expect((try? view.inspect().vStack()) == nil)
    }
}
