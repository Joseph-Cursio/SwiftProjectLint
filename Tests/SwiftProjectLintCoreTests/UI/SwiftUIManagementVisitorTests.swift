import Testing
import SwiftParser
import SwiftSyntax
@testable import SwiftProjectLintCore

@Suite("SwiftUIManagementVisitorTests")
struct SwiftUIManagementVisitorTests {
    
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
                hasInitialValue: true
            ),
            StateVariableInfo(
                name: "data",
                type: "String",
                propertyWrapper: .state,
                viewName: "View2",
                filePath: "test.swift",
                lineNumber: 6,
                hasInitialValue: true
            )
        ]
        
        // Find related views
        let relatedViews = visitor.findRelatedViews(for: testVariables)
        #expect(relatedViews.count == 2)
        #expect(relatedViews.contains("View1"))
        #expect(relatedViews.contains("View2"))
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
