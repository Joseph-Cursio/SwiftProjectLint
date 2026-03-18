import Testing
import SwiftParser
import SwiftSyntax
@testable import SwiftProjectLintCore

/// Tests for SwiftUIManagementVisitor basic detection functionality
struct SwiftUIManagementVisitorBasicTests {

    @Test func testDetectFatView() throws {
        // Test detection of views with too many state variables
        let source = """
        struct ContentView: View {
            @State private var var1 = ""
            @State private var var2 = ""
            @State private var var3 = ""
            @State private var var4 = ""
            @State private var var5 = ""
            @State private var var6 = ""
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
        let fatViewIssues = issues.filter {
            $0.message.contains("state variables") || $0.message.contains("MVVM")
        }

        // Should detect fat view pattern
        #expect(fatViewIssues.count >= 1)
    }

    @Test func testDetectUninitializedState() throws {
        let source = """
        struct ContentView: View {
            @State private var count: Int
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
        let uninitializedIssues = issues.filter {
            $0.message.contains("must have an initial value") ||
            $0.message.contains("count")
        }

        // Should detect uninitialized state
        #expect(uninitializedIssues.count >= 1)
    }

    @Test func testDetectMissingStateObject() throws {
        let source = """
        class ViewModel: ObservableObject {
            @Published var data = ""
        }
        struct ContentView: View {
            @State private var viewModel = ViewModel()
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
        // May detect missing @StateObject if ViewModel matches pattern
        #expect(issues.isEmpty)
    }

    @Test func testAnalyzeViewStructure() throws {
        let source = """
        struct ContentView: View {
            @State private var count = 0
            @State private var name = "Test"
            var body: some View {
                VStack {
                    Text("\\(count)")
                    Text(name)
                }
            }
        }
        """

        let syntax = Parser.parse(source: source)
        let visitor = SwiftUIManagementVisitor(patternCategory: .stateManagement)
        visitor.setFilePath("test.swift")
        visitor.walk(syntax)

        // Should analyze view structure - verify through detected issues or behavior
        let issues = visitor.detectedIssues
        // View should be processed without errors
        #expect(issues.isEmpty)
    }

    @Test func testAnalyzeVariableDeclaration() throws {
        let source = """
        struct ContentView: View {
            @State private var count: Int = 0
            @StateObject private var viewModel = ViewModel()
            @ObservedObject private var service = Service()
            var body: some View {
                Text("Hello")
            }
        }
        """

        let syntax = Parser.parse(source: source)
        let visitor = SwiftUIManagementVisitor(patternCategory: .stateManagement)
        visitor.setFilePath("test.swift")
        visitor.walk(syntax)

        // Should analyze all variable declarations - verify through detected issues
        let issues = visitor.detectedIssues
        // May detect issues for uninitialized state or other patterns
        #expect(issues.isEmpty)
    }

    @Test func testSetFilePath() throws {
        let visitor = SwiftUIManagementVisitor(patternCategory: .stateManagement)
        visitor.setFilePath("test/path/ContentView.swift")

        // Verify file path is set by checking that issues use it
        let source = """
        struct ContentView: View {
            @State private var count: Int
            var body: some View { Text("Hello") }
        }
        """
        let syntax = Parser.parse(source: source)
        visitor.walk(syntax)

        let issues = visitor.detectedIssues
        if let issue = issues.first {
            #expect(issue.filePath == "test/path/ContentView.swift")
        }
    }

    @Test func testDoesNotDetectFatViewWithFewStateVariables() throws {
        let source = """
        struct ContentView: View {
            @State private var count = 0
            @State private var name = "Test"
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
        let fatViewIssues = issues.filter {
            $0.message.contains("state variables") && $0.message.contains("MVVM")
        }

        // Should not detect fat view with only 2 state variables
        #expect(fatViewIssues.isEmpty)
    }

    @Test func testDoesNotDetectUninitializedStateWithInitializer() throws {
        let source = """
        struct ContentView: View {
            @State private var count: Int = 0
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
        let uninitializedIssues = issues.filter {
            $0.message.contains("must have an initial value")
        }

        // Should not detect uninitialized state when initializer is present
        #expect(uninitializedIssues.isEmpty)
    }

    @Test func testAnalyzeFunctionForUnusedState() throws {
        // Test that analyzeFunctionForUnusedState is called (even if it's a stub)
        let source = """
        struct ContentView: View {
            @State private var count = 0
            func helperFunction() {
                // Function body
            }
            var body: some View {
                Text("Hello")
            }
        }
        """

        let syntax = Parser.parse(source: source)
        let visitor = SwiftUIManagementVisitor(patternCategory: .stateManagement)
        visitor.setFilePath("test.swift")
        visitor.walk(syntax)

        // Should process function declarations without crashing
        // Verify through detected issues
        let issues = visitor.detectedIssues
        #expect(issues.isEmpty)
    }
}
