import Testing
import Foundation
import SwiftSyntax
import SwiftParser
@testable import SwiftProjectLintCore

struct StateVariableVisitorTests {
    @Test func testBasicStateVariableDetection() async throws {
        let sourceCode = """
        struct ContentView: View {
            @State private var isShowingSheet = false
            @State private var counter = 0
            
            var body: some View {
                Text("Hello")
            }
        }
        """
        
        let stateVariables = await extractStateVariables(from: sourceCode, viewName: "ContentView")
        
        // Debug information using NSLog to show actual values
        NSLog("=== DEBUG: testBasicStateVariableDetection ===")
        NSLog("Expected count: 2, Actual count: \(stateVariables.count)")
        NSLog("All variables: \(stateVariables.map { "\($0.name):\($0.propertyWrapper):\($0.type)" })")
        
        #expect(stateVariables.count == 2)
        
        let isShowingSheet = stateVariables.first { $0.name == "isShowingSheet" }
        if isShowingSheet == nil {
            #expect(false, "isShowingSheet not found. Available variables: \(stateVariables.map { $0.name })")
        } else if isShowingSheet?.propertyWrapper != "@State" {
            #expect(false, "isShowingSheet wrapper mismatch. Expected: '@State', Actual: '\(isShowingSheet?.propertyWrapper ?? "nil")'")
        } else if isShowingSheet?.type != "Bool" {
            #expect(false, "isShowingSheet type mismatch. Expected: 'Bool', Actual: '\(isShowingSheet?.type ?? "nil")'")
        }
        
        let counter = stateVariables.first { $0.name == "counter" }
        if counter == nil {
            #expect(false, "counter not found. Available variables: \(stateVariables.map { $0.name })")
        } else if counter?.propertyWrapper != "@State" {
            #expect(false, "counter wrapper mismatch. Expected: '@State', Actual: '\(counter?.propertyWrapper ?? "nil")'")
        } else if counter?.type != "Int" {
            #expect(false, "counter type mismatch. Expected: 'Int', Actual: '\(counter?.type ?? "nil")'")
        }
    }
    
    @Test func testStateObjectDetection() async throws {
        let sourceCode = """
        struct ContentView: View {
            @StateObject private var viewModel = ContentViewModel()
            
            var body: some View {
                Text("Hello")
            }
        }
        """
        
        let stateVariables = await extractStateVariables(from: sourceCode, viewName: "ContentView")
        
        #expect(stateVariables.count == 1)
        #expect(stateVariables[0].name == "viewModel")
        #expect(stateVariables[0].propertyWrapper == "@StateObject")
        #expect(stateVariables[0].type == "ContentViewModel")
    }
    
    @Test func testObservedObjectDetection() async throws {
        let sourceCode = """
        struct ContentView: View {
            @ObservedObject var dataManager: DataManager
            
            var body: some View {
                Text("Hello")
            }
        }
        """
        
        let stateVariables = await extractStateVariables(from: sourceCode, viewName: "ContentView")
        
        #expect(stateVariables.count == 1)
        #expect(stateVariables[0].name == "dataManager")
        #expect(stateVariables[0].propertyWrapper == "@ObservedObject")
        #expect(stateVariables[0].type == "DataManager")
    }
    
    @Test func testEnvironmentObjectDetection() async throws {
        let sourceCode = """
        struct ContentView: View {
            @EnvironmentObject var appState: AppState
            
            var body: some View {
                Text("Hello")
            }
        }
        """
        
        let stateVariables = await extractStateVariables(from: sourceCode, viewName: "ContentView")
        
        #expect(stateVariables.count == 1)
        #expect(stateVariables[0].name == "appState")
        #expect(stateVariables[0].propertyWrapper == "@EnvironmentObject")
        #expect(stateVariables[0].type == "AppState")
    }
    
    @Test func testBindingDetection() async throws {
        let sourceCode = """
        struct ContentView: View {
            @Binding var isPresented: Bool
            
            var body: some View {
                Text("Hello")
            }
        }
        """
        
        let stateVariables = await extractStateVariables(from: sourceCode, viewName: "ContentView")
        
        #expect(stateVariables.count == 1)
        #expect(stateVariables[0].name == "isPresented")
        #expect(stateVariables[0].propertyWrapper == "@Binding")
        #expect(stateVariables[0].type == "Bool")
    }
    
    @Test func testEnvironmentDetection() async throws {
        let sourceCode = """
        struct ContentView: View {
            @Environment(\\.colorScheme) var colorScheme
            @Environment(\\.locale) var locale
            
            var body: some View {
                Text("Hello")
            }
        }
        """
        
        let stateVariables = await extractStateVariables(from: sourceCode, viewName: "ContentView")
        
        #expect(stateVariables.count == 2)
        
        let colorScheme = stateVariables.first { $0.name == "colorScheme" }
        #expect(colorScheme != nil)
        #expect(colorScheme?.propertyWrapper == "@Environment")
        
        let locale = stateVariables.first { $0.name == "locale" }
        #expect(locale != nil)
        #expect(locale?.propertyWrapper == "@Environment")
    }
    
    @Test func testFocusStateDetection() async throws {
        let sourceCode = """
        struct ContentView: View {
            @FocusState private var isFocused: Bool
            @FocusState private var focusedField: Field?
            
            var body: some View {
                Text("Hello")
            }
        }
        """
        
        let stateVariables = await extractStateVariables(from: sourceCode, viewName: "ContentView")
        
        #expect(stateVariables.count == 2)
        
        let isFocused = stateVariables.first { $0.name == "isFocused" }
        #expect(isFocused != nil)
        #expect(isFocused?.propertyWrapper == "@FocusState")
        #expect(isFocused?.type == "Bool")
        
        let focusedField = stateVariables.first { $0.name == "focusedField" }
        #expect(focusedField != nil)
        #expect(focusedField?.propertyWrapper == "@FocusState")
        #expect(focusedField?.type == "Field?")
    }
    
    @Test func testGestureStateDetection() async throws {
        let sourceCode = """
        struct ContentView: View {
            @GestureState private var dragOffset = CGSize.zero
            @GestureState private var isPressed = false
            
            var body: some View {
                Text("Hello")
            }
        }
        """
        
        let stateVariables = await extractStateVariables(from: sourceCode, viewName: "ContentView")
        
        #expect(stateVariables.count == 2)
        
        let dragOffset = stateVariables.first { $0.name == "dragOffset" }
        #expect(dragOffset != nil)
        #expect(dragOffset?.propertyWrapper == "@GestureState")
        #expect(dragOffset?.type == "CGSize")
        
        let isPressed = stateVariables.first { $0.name == "isPressed" }
        #expect(isPressed != nil)
        #expect(isPressed?.propertyWrapper == "@GestureState")
        #expect(isPressed?.type == "Bool")
    }
    
    @Test func testNamespaceDetection() async throws {
        let sourceCode = """
        struct ContentView: View {
            @Namespace private var animation
            
            var body: some View {
                Text("Hello")
            }
        }
        """
        
        let stateVariables = await extractStateVariables(from: sourceCode, viewName: "ContentView")
        
        #expect(stateVariables.count == 1)
        #expect(stateVariables[0].name == "animation")
        #expect(stateVariables[0].propertyWrapper == "@Namespace")
    }
    
    @Test func testAppStorageDetection() async throws {
        let sourceCode = """
        struct ContentView: View {
            @AppStorage("username") private var username = ""
            @AppStorage("isFirstLaunch") private var isFirstLaunch = true
            
            var body: some View {
                Text("Hello")
            }
        }
        """
        
        let stateVariables = await extractStateVariables(from: sourceCode, viewName: "ContentView")
        
        #expect(stateVariables.count == 2)
        
        let username = stateVariables.first { $0.name == "username" }
        #expect(username != nil)
        #expect(username?.propertyWrapper == "@AppStorage")
        #expect(username?.type == "String")
        
        let isFirstLaunch = stateVariables.first { $0.name == "isFirstLaunch" }
        #expect(isFirstLaunch != nil)
        #expect(isFirstLaunch?.propertyWrapper == "@AppStorage")
        #expect(isFirstLaunch?.type == "Bool")
    }
    
    @Test func testFetchRequestDetection() async throws {
        let sourceCode = """
        struct ContentView: View {
            @FetchRequest(
                sortDescriptors: [NSSortDescriptor(keyPath: \\Item.timestamp, ascending: true)],
                animation: .default)
            private var items: FetchedResults<Item>
            
            var body: some View {
                Text("Hello")
            }
        }
        """
        
        let stateVariables = await extractStateVariables(from: sourceCode, viewName: "ContentView")
        
        #expect(stateVariables.count == 1)
        #expect(stateVariables[0].name == "items")
        #expect(stateVariables[0].propertyWrapper == "@FetchRequest")
    }
    
    @Test func testMultiplePropertyWrappers() async throws {
        let sourceCode = """
        struct ContentView: View {
            @State private var counter = 0
            @StateObject private var viewModel = ContentViewModel()
            @ObservedObject var dataManager: DataManager
            @EnvironmentObject var appState: AppState
            @Binding var isPresented: Bool
            @Environment(\\.colorScheme) var colorScheme
            @FocusState private var isFocused: Bool
            @GestureState private var dragOffset = CGSize.zero
            @Namespace private var animation
            @AppStorage("username") private var username = ""
            
            var body: some View {
                Text("Hello")
            }
        }
        """
        
        let stateVariables = await extractStateVariables(from: sourceCode, viewName: "ContentView")
        
        #expect(stateVariables.count == 10)
        
        let wrappers = Set(stateVariables.map { $0.propertyWrapper })
        let expectedWrappers: Set<String> = [
            "@State", "@StateObject", "@ObservedObject", "@EnvironmentObject",
            "@Binding", "@Environment", "@FocusState", "@GestureState",
            "@Namespace", "@AppStorage"
        ]
        
        #expect(wrappers == expectedWrappers)
    }
    
    @Test func testStateVariableSummary() async throws {
        let sourceCode = """
        struct ContentView: View {
            @State private var counter = 0
            @State private var isShowing = false
            @StateObject private var viewModel = ContentViewModel()
            @ObservedObject var dataManager: DataManager
            @EnvironmentObject var appState: AppState
            
            var body: some View {
                Text("Hello")
            }
        }
        """
        
        let visitor = await createVisitor(from: sourceCode, viewName: "ContentView")
        let summary = visitor.getStateVariableSummary()
        
        #expect(summary["@State"] == 2)
        #expect(summary["@StateObject"] == 1)
        #expect(summary["@ObservedObject"] == 1)
        #expect(summary["@EnvironmentObject"] == 1)
    }
    
    @Test func testFilterByPropertyWrapper() async throws {
        let sourceCode = """
        struct ContentView: View {
            @State private var counter = 0
            @StateObject private var viewModel = ContentViewModel()
            @ObservedObject var dataManager: DataManager
            
            var body: some View {
                Text("Hello")
            }
        }
        """
        
        let visitor = await createVisitor(from: sourceCode, viewName: "ContentView")
        let stateVariables = visitor.getStateVariables(withPropertyWrapper: "@State")
        
        #expect(stateVariables.count == 1)
        #expect(stateVariables[0].name == "counter")
    }
    
    @Test func testEnvironmentObjectCandidates() async throws {
        let sourceCode = """
        struct ContentView: View {
            @StateObject private var userManager = UserManager()
            @ObservedObject var dataManager: DataManager
            @State private var counter = 0
            
            var body: some View {
                Text("Hello")
            }
        }
        """
        
        let visitor = await createVisitor(from: sourceCode, viewName: "ContentView")
        
        let candidates = visitor.getPotentialEnvironmentObjectCandidates()
        
        #expect(candidates.count == 2)
        
        let candidateNames = Set(candidates.map { $0.name })
        if candidateNames != ["userManager", "dataManager"] {
            #expect(false, "Expected candidate names [userManager, dataManager], got \(candidateNames)")
        }
        #expect(candidateNames == ["userManager", "dataManager"])
    }
    
    @Test func testLineNumberCalculation() async throws {
        let sourceCode = """
        struct ContentView: View {
            @State private var counter = 0
            
            var body: some View {
                Text("Hello")
            }
        }
        """
        
        let stateVariables = await extractStateVariables(from: sourceCode, viewName: "ContentView")
        
        #expect(stateVariables.count == 1)
        #expect(stateVariables[0].lineNumber > 0)
    }
    
    @Test func testUnknownTypeHandling() async throws {
        let sourceCode = """
        struct ContentView: View {
            @State private var unknownVar = [1, 2, 3].map { $0 * 2 }
            
            var body: some View {
                Text("Hello")
            }
        }
        """
        
        // This should handle unknown types gracefully with default config
        let visitor = await createVisitor(from: sourceCode, viewName: "ContentView")
        #expect(visitor.stateVariables.count == 1)
        #expect(visitor.stateVariables[0].type == "Unknown")
        #expect(visitor.stateVariables[0].name == "unknownVar")
    }
    
    // MARK: - Helper Methods
    
    @MainActor
    private func extractStateVariables(from sourceCode: String, viewName: String) -> [StateVariable] {
        let visitor = createVisitor(from: sourceCode, viewName: viewName)
        return visitor.stateVariables
    }
    
    @MainActor
    private func createVisitor(from sourceCode: String, viewName: String) -> StateVariableVisitor {
        let sourceFile = Parser.parse(source: sourceCode)
        
        let visitor = StateVariableVisitor(
            viewName: viewName,
            filePath: "test.swift",
            sourceContents: sourceCode,
            config: .default
        )
        visitor.walk(sourceFile)
        return visitor
    }
} 