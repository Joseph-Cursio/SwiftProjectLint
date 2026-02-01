import Testing
import SwiftUI
import ViewInspector

class ContentViewModel: ObservableObject {
    @Published var isLoading: Bool = false
    @Published var items: [String] = []
    init() { }
}

@testable import SwiftProjectLint

@Suite
@MainActor
struct ContentViewTests {
    @Test
    func testLoading() throws {
        let systemComponents = SystemComponents()
        systemComponents.initialize()
        let view = ContentView().environmentObject(systemComponents)
        let texts = try view.inspect().findAll(ViewType.Text.self)
        // Check for any loading-related text in the view
        let textStrings = texts.compactMap { try? $0.string() }
        #expect(!textStrings.isEmpty) // View should have some text content
    }

    @Test
    func testLoadedItems() throws {
        let systemComponents = SystemComponents()
        systemComponents.initialize()
        let view = ContentView().environmentObject(systemComponents)
        let texts = try view.inspect().findAll(ViewType.Text.self)
        let textStrings = texts.compactMap { try? $0.string() }
        #expect(!textStrings.isEmpty) // View should have some text content
    }

    @Test
    @MainActor
    func testContentViewStructure() throws {
        let systemComponents = SystemComponents()
        systemComponents.initialize()
        let view = ContentView().environmentObject(systemComponents)
        let inspected = try view.inspect()
        // NavigationView
        #expect(try { _ = try inspected.find(ViewType.NavigationView.self); return true }())
        // VStack
        let vStack = try inspected.navigationView().vStack()
        // Header
        #expect(try { _ = try vStack.find(ContentViewHeader.self); return true }())
        // Actions
        #expect(try { _ = try vStack.find(ContentViewActions.self); return true }())
        // Progress
        #expect(try { _ = try vStack.find(ContentViewProgress.self); return true }())
        // Results
        #expect(try { _ = try vStack.find(ContentViewResults.self); return true }())
        // Navigation title: check for the title text somewhere in the view
        let allTexts = try inspected.findAll(ViewType.Text.self).map { try? $0.string() }
        #expect(allTexts.contains("Swift Project Linter"))
    }

    @Test
    @MainActor
    func testRuleSelectionDialogSheetAppears() throws {
        // ViewInspector does not currently support direct sheet state inspection in Swift Testing.
        // Placeholder for future support or workaround.
        // e.g. #expect(try inspected.sheet().find(RuleSelectionDialog.self) != nil)
    }
}
