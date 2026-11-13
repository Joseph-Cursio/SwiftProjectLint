import SwiftParser
import SwiftProjectLintModels
@testable import SwiftProjectLintRules
import SwiftProjectLintVisitors
import SwiftSyntax
import Testing

/// Tests for `SwiftUIManagementVisitor`'s missing-@StateObject check. Duplicate state across views
/// is `RelatedDuplicateStateVisitor`, tested in `RelatedDuplicateStateVisitorTests`.
struct SwiftUIManagementVisitorStateObjectTests {

    @Test func testCheckForMissingStateObjectWithManager() {
        let source = """
        class DataManager: ObservableObject {
            @Published var data = ""
        }
        struct ContentView: View {
            @State private var manager = DataManager()
            var body: some View {
                Text("Hello")
            }
        }
        """

        let syntax = Parser.parse(source: source)
        let visitor = SwiftUIManagementVisitor(patternCategory: .stateManagement)
        visitor.setFilePath("test.swift")
        visitor.walk(syntax)

        let issues = visitor.detectedIssues
        // May detect missing @StateObject for Manager suffix
        #expect(issues.isEmpty)
    }

    @Test func testCheckForMissingStateObjectWithService() {
        let source = """
        class NetworkService: ObservableObject {
            @Published var status = ""
        }
        struct ContentView: View {
            @State private var service = NetworkService()
            var body: some View {
                Text("Hello")
            }
        }
        """

        let syntax = Parser.parse(source: source)
        let visitor = SwiftUIManagementVisitor(patternCategory: .stateManagement)
        visitor.setFilePath("test.swift")
        visitor.walk(syntax)

        let issues = visitor.detectedIssues
        // May detect missing @StateObject for Service suffix
        #expect(issues.isEmpty)
    }

    @Test func testCheckForMissingStateObjectWithViewModel() {
        let source = """
        class MyViewModel: ObservableObject {
            @Published var data = ""
        }
        struct ContentView: View {
            @State private var viewModel = MyViewModel()
            var body: some View {
                Text("Hello")
            }
        }
        """

        let syntax = Parser.parse(source: source)
        let visitor = SwiftUIManagementVisitor(patternCategory: .stateManagement)
        visitor.setFilePath("test.swift")
        visitor.walk(syntax)

        let issues = visitor.detectedIssues
        // May detect missing @StateObject for ViewModel suffix
        #expect(issues.isEmpty)
    }
}
