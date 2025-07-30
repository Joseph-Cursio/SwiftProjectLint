import Testing
import SwiftUI
import ViewInspector

@testable import SwiftProjectLint

@Suite
@MainActor
struct ContentViewActionsTests {
    @Test
    func testActionsWithoutSelectedDirectory() throws {
        let view = ContentViewActions(
            selectedDirectory: "",
            onSelectRules: {},
            onSelectDirectory: {},
            onAnalyzeProject: {}
        )
        let inspected = try view.inspect()
        let vStack = try inspected.vStack()
        // Select Rules button
        let selectRulesButton = try vStack.button(0)
        #expect(try selectRulesButton.labelView().text().string() == "Select Rules")
        // Main action button (folder selection)
        let mainActionButton = try vStack.button(1)
        #expect(try mainActionButton.labelView().text().string() == "Run Project Analysis by Selecting a Folder...")
    }

    @Test
    func testActionsWithSelectedDirectory() throws {
        let view = ContentViewActions(
            selectedDirectory: "/Users/test/MyProject",
            onSelectRules: {},
            onSelectDirectory: {},
            onAnalyzeProject: {}
        )
        let inspected = try view.inspect()
        let vStack = try inspected.vStack()
        // Select Rules button
        let selectRulesButton = try vStack.button(0)
        #expect(try selectRulesButton.labelView().text().string() == "Select Rules")
        // Main action button (analyze project)
        let mainActionButton = try vStack.button(1)
        #expect(try mainActionButton.labelView().text().string() == "Analyze MyProject")
    }
} 
