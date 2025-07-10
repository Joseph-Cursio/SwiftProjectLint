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
}
