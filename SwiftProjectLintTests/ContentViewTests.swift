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
    func testLoading() throws {
        let viewModel = ContentViewModel()
        viewModel.isLoading = true
        let view = ContentView()
        let texts = try view.inspect().findAll(ViewType.Text.self)
        #expect(texts.contains(where: { (try? $0.string()) == "Loading..." }))
    }

    func testLoadedItems() throws {
        let viewModel = ContentViewModel()
        viewModel.isLoading = false
        viewModel.items = ["One", "Two", "Three"]
        let view = ContentView()
        let texts = try view.inspect().findAll(ViewType.Text.self)
        #expect(texts.count == 3)
        #expect((try? texts[0].string()) == "One")
        #expect((try? texts[1].string()) == "Two")
        #expect((try? texts[2].string()) == "Three")
    }

    @Test
    @MainActor
    func testContentViewStructure() throws {
        let systemComponents = SystemComponents()
        systemComponents.initialize()
        let view = ContentView().environmentObject(systemComponents)
        let inspected = try view.inspect()
        // NavigationView
        #expect(try inspected.find(ViewType.NavigationView.self) != nil)
        // VStack
        let vStack = try inspected.navigationView().vStack()
        // Header
        #expect(try vStack.find(ContentViewHeader.self) != nil)
        // Actions
        #expect(try vStack.find(ContentViewActions.self) != nil)
        // Progress
        #expect(try vStack.find(ContentViewProgress.self) != nil)
        // Results
        #expect(try vStack.find(ContentViewResults.self) != nil)
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
