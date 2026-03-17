import Testing
import SwiftUI
import ViewInspector

@testable import SwiftProjectLint

@Suite("ContentViewActions Tests")
@MainActor
struct ContentViewActionsTests {
    @Test("shows Select Rules button and folder selection when no directory is selected")
    func actionsWithoutSelectedDirectory() throws {
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

    @Test("shows Select Rules button and analyze button when directory is selected")
    func actionsWithSelectedDirectory() throws {
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

    @Test("tapping Select Rules button invokes the onSelectRules callback")
    func selectRulesCallbackInvoked() throws {
        var callbackCalled = false
        let view = ContentViewActions(
            selectedDirectory: "",
            onSelectRules: { callbackCalled = true },
            onSelectDirectory: {},
            onAnalyzeProject: {}
        )
        let inspected = try view.inspect()
        let selectRulesButton = try inspected.vStack().button(0)
        try selectRulesButton.tap()
        #expect(callbackCalled, "onSelectRules should be called when the button is tapped")
    }

    @Test("tapping folder selection button invokes the onSelectDirectory callback")
    func selectDirectoryCallbackInvoked() throws {
        var callbackCalled = false
        let view = ContentViewActions(
            selectedDirectory: "",
            onSelectRules: {},
            onSelectDirectory: { callbackCalled = true },
            onAnalyzeProject: {}
        )
        let inspected = try view.inspect()
        let mainActionButton = try inspected.vStack().button(1)
        try mainActionButton.tap()
        #expect(callbackCalled, "onSelectDirectory should be called when the button is tapped")
    }

    @Test("tapping analyze button invokes the onAnalyzeProject callback")
    func analyzeProjectCallbackInvoked() throws {
        var callbackCalled = false
        let view = ContentViewActions(
            selectedDirectory: "/Users/test/SomeProject",
            onSelectRules: {},
            onSelectDirectory: {},
            onAnalyzeProject: { callbackCalled = true }
        )
        let inspected = try view.inspect()
        let analyzeButton = try inspected.vStack().button(1)
        try analyzeButton.tap()
        #expect(callbackCalled, "onAnalyzeProject should be called when the button is tapped")
    }

    @Test("analyze button shows the last path component as the project name")
    func analyzeButtonShowsProjectName() throws {
        let view = ContentViewActions(
            selectedDirectory: "/Users/developer/projects/AwesomeApp",
            onSelectRules: {},
            onSelectDirectory: {},
            onAnalyzeProject: {}
        )
        let inspected = try view.inspect()
        let analyzeButton = try inspected.vStack().button(1)
        let buttonText = try analyzeButton.labelView().text().string()
        #expect(buttonText == "Analyze AwesomeApp")
    }

    @Test("VStack contains exactly two buttons")
    func exactlyTwoButtons() throws {
        let view = ContentViewActions(
            selectedDirectory: "",
            onSelectRules: {},
            onSelectDirectory: {},
            onAnalyzeProject: {}
        )
        let inspected = try view.inspect()
        let buttons = inspected.findAll(ViewType.Button.self)
        #expect(buttons.count == 2)
    }

    @Test("VStack contains exactly two buttons when directory is selected")
    func exactlyTwoButtonsWithDirectory() throws {
        let view = ContentViewActions(
            selectedDirectory: "/some/path",
            onSelectRules: {},
            onSelectDirectory: {},
            onAnalyzeProject: {}
        )
        let inspected = try view.inspect()
        let buttons = inspected.findAll(ViewType.Button.self)
        #expect(buttons.count == 2)
    }

    @Test("accessibility identifiers are set correctly without directory")
    func accessibilityIdentifiersWithoutDirectory() throws {
        let view = ContentViewActions(
            selectedDirectory: "",
            onSelectRules: {},
            onSelectDirectory: {},
            onAnalyzeProject: {}
        )
        let inspected = try view.inspect()
        let buttons = inspected.findAll(ViewType.Button.self)
        let identifiers = buttons.compactMap { try? $0.accessibilityIdentifier() }
        #expect(identifiers.contains("selectRulesButton"))
        #expect(identifiers.contains("mainActionButton"))
    }

    @Test("accessibility identifiers are set correctly with directory")
    func accessibilityIdentifiersWithDirectory() throws {
        let view = ContentViewActions(
            selectedDirectory: "/some/path",
            onSelectRules: {},
            onSelectDirectory: {},
            onAnalyzeProject: {}
        )
        let inspected = try view.inspect()
        let buttons = inspected.findAll(ViewType.Button.self)
        let identifiers = buttons.compactMap { try? $0.accessibilityIdentifier() }
        #expect(identifiers.contains("selectRulesButton"))
        #expect(identifiers.contains("mainActionButton"))
    }
}
