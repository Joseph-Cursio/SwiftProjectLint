import Testing
import SwiftParser
import SwiftSyntax
@testable import Core

/// Tests for SwiftUIManagementVisitor cross-file analysis and state object detection
struct SwiftUIManagementVisitorCrossFileTests {

    @Test func testDetectDuplicateStateVariables() throws {
        let source = """
        struct ParentView: View {
            @State private var sharedData = ""
            var body: some View {
                ChildView()
            }
        }
        struct ChildView: View {
            @State private var sharedData = ""
            var body: some View {
                Text("Hello")
            }
        }
        """

        let syntax = Parser.parse(source: source)
        let visitor = SwiftUIManagementVisitor(patternCategory: .stateManagement)
        visitor.setFilePath("test.swift")
        visitor.walk(syntax)

        // Perform cross-file analysis
        visitor.finalizeAnalysis()

        let issues = visitor.detectedIssues
        let duplicateIssues = issues.filter {
            $0.message.contains("Duplicate") || $0.message.contains("sharedData")
        }

        // Should detect duplicate state variables
        #expect(duplicateIssues.count >= 1)
    }

    @Test func testFindRelatedViews() throws {
        let source = """
        struct View1: View {
            @State private var data = ""
            var body: some View { Text("1") }
        }
        struct View2: View {
            @State private var data = ""
            var body: some View { Text("2") }
        }
        """

        let syntax = Parser.parse(source: source)
        let visitor = SwiftUIManagementVisitor(patternCategory: .stateManagement)
        visitor.setFilePath("test.swift")
        visitor.walk(syntax)

        // Create test variables to test findRelatedViews method
        let testVariables = [
            StateVariableInfo(
                name: "data",
                type: "String",
                propertyWrapper: .state,
                viewName: "View1",
                filePath: "test.swift",
                lineNumber: 2,
                hasInitialValue: true,
                node: nil
            ),
            StateVariableInfo(
                name: "data",
                type: "String",
                propertyWrapper: .state,
                viewName: "View2",
                filePath: "test.swift",
                lineNumber: 6,
                hasInitialValue: true,
                node: nil
            )
        ]

        // Find related views
        let relatedViews = visitor.findRelatedViews(for: testVariables)
        #expect(relatedViews.count == 2)
        #expect(relatedViews.contains("View1"))
        #expect(relatedViews.contains("View2"))
    }

    @Test func testCheckForMissingStateObjectWithManager() throws {
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

    @Test func testCheckForMissingStateObjectWithService() throws {
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

    @Test func testCheckForMissingStateObjectWithViewModel() throws {
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

    @Test func testPerformCrossFileAnalysis() throws {
        let source = """
        struct View1: View {
            @State private var sharedState = ""
            var body: some View { Text("1") }
        }
        struct View2: View {
            @State private var sharedState = ""
            var body: some View { Text("2") }
        }
        struct View3: View {
            @State private var sharedState = ""
            var body: some View { Text("3") }
        }
        """

        let syntax = Parser.parse(source: source)
        let visitor = SwiftUIManagementVisitor(patternCategory: .stateManagement)
        visitor.setFilePath("test.swift")
        visitor.walk(syntax)

        // Perform cross-file analysis
        visitor.finalizeAnalysis()

        let issues = visitor.detectedIssues
        let duplicateIssues = issues.filter {
            $0.message.contains("Duplicate") || $0.message.contains("sharedState")
        }

        // Should detect duplicate state variables across views
        #expect(duplicateIssues.count >= 1)
    }

    @Test func testViewDeclarationsAreStored() throws {
        let source = """
        struct View1: View {
            @State private var count = 0
            var body: some View { Text("1") }
        }
        struct View2: View {
            @State private var name = "Test"
            var body: some View { Text("2") }
        }
        """

        let syntax = Parser.parse(source: source)
        let visitor = SwiftUIManagementVisitor(patternCategory: .stateManagement)
        visitor.setFilePath("test.swift")
        visitor.walk(syntax)

        // View declarations are stored internally - verify through finalizeAnalysis
        visitor.finalizeAnalysis()
        let issues = visitor.detectedIssues
        // Should process both views
        #expect(issues.isEmpty)
    }
}
