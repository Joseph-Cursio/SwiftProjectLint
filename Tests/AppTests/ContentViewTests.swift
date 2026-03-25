import Testing
import SwiftUI
import ViewInspector
import Core

@testable import App

@Suite("ContentView Tests")
@MainActor
struct ContentViewTests {
    @Test("view renders text content when environment object is provided")
    func rendersTextContent() async throws {
        let systemComponents = SystemComponents()
        await systemComponents.initialize()
        let view = ContentView().environmentObject(systemComponents)
        let inspected = try view.inspect()
        let texts = inspected.findAll(ViewType.Text.self)
        let textStrings = texts.compactMap { try? $0.string() }
        #expect(textStrings.isEmpty == false)

    }

    @Test("view contains expected child views in its VStack")
    func contentViewStructure() async throws {
        let systemComponents = SystemComponents()
        await systemComponents.initialize()
        let view = ContentView().environmentObject(systemComponents)
        let inspected = try view.inspect()
        // NavigationStack
        _ = try inspected.find(ViewType.NavigationStack.self)
        // VStack with child views
        let vStack = try inspected.navigationStack().vStack()
        _ = try vStack.find(ContentViewHeader.self)
        _ = try vStack.find(ContentViewActions.self)
        _ = try vStack.find(ContentViewProgress.self)
        _ = try vStack.find(ContentViewResults.self)
    }

    @Test("view displays the app title text")
    func displaysAppTitle() async throws {
        let systemComponents = SystemComponents()
        await systemComponents.initialize()
        let view = ContentView().environmentObject(systemComponents)
        let inspected = try view.inspect()
        let allTexts = inspected.findAll(ViewType.Text.self).compactMap { try? $0.string() }
        #expect(allTexts.contains("Swift Project Linter"))
    }

    @Test("view displays the subtitle description text")
    func displaysSubtitleDescription() async throws {
        let systemComponents = SystemComponents()
        await systemComponents.initialize()
        let view = ContentView().environmentObject(systemComponents)
        let inspected = try view.inspect()
        let allTexts = inspected.findAll(ViewType.Text.self).compactMap { try? $0.string() }
        #expect(allTexts.contains("Detect cross-file issues and architectural problems"))
    }

    @Test("view renders without crashing with uninitialized system components")
    func rendersWithUninitializedComponents() throws {
        let systemComponents = SystemComponents()
        // Deliberately NOT calling initialize()
        let view = ContentView().environmentObject(systemComponents)
        let inspected = try view.inspect()
        let texts = inspected.findAll(ViewType.Text.self)
        #expect(texts.isEmpty == false)

    }

    @Test("view shows Select Rules button")
    func showsSelectRulesButton() async throws {
        let systemComponents = SystemComponents()
        await systemComponents.initialize()
        let view = ContentView().environmentObject(systemComponents)
        let inspected = try view.inspect()
        let buttons = inspected.findAll(ViewType.Button.self)
        let buttonLabels = buttons.compactMap { try? $0.labelView().text().string() }
        #expect(buttonLabels.contains("Select Rules"))
    }

    @Test("view shows folder selection button initially when no directory is set")
    func showsFolderSelectionButton() async throws {
        let systemComponents = SystemComponents()
        await systemComponents.initialize()
        let view = ContentView().environmentObject(systemComponents)
        let inspected = try view.inspect()
        let buttons = inspected.findAll(ViewType.Button.self)
        let buttonLabels = buttons.compactMap { try? $0.labelView().text().string() }
        #expect(buttonLabels.contains("Run Project Analysis by Selecting a Folder..."))
    }

    @Test("ContentViewPreviewHost creates a view with environment object")
    func previewHostCreatesView() throws {
        let previewHost = ContentViewPreviewHost()
        let inspected = try previewHost.inspect()
        // The preview host wraps a ContentView
        _ = try inspected.find(ContentView.self)
    }

    @Test("testHostView returns a valid view")
    func testHostViewReturnsValidView() throws {
        let hostView = ContentView.testHostView()
        // Should be inspectable - it returns a ContentViewPreviewHost
        let inspected = try hostView.inspect()
        let texts = inspected.findAll(ViewType.Text.self)
        #expect(texts.isEmpty == false)

    }
}
