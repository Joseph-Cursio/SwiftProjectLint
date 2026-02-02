import Testing
import Foundation
import SwiftSyntax
import SwiftParser
@testable import SwiftProjectLintCore

@Suite
@MainActor
struct StateVariableVisitorTests {
    
    // MARK: - Type Extraction from Annotations
    
    @Test func testExtractTypeFromExplicitAnnotation() throws {
        let source = """
        struct TestView: View {
            @State private var count: Int = 0
            var body: some View { Text("Test") }
        }
        """
        
        let visitor = createVisitor(for: source)
        let stateVars = visitor.stateVariables
        
        #expect(stateVars.count == 1)
        #expect(stateVars.first?.type == "Int")
        #expect(stateVars.first?.name == "count")
    }
    
    @Test func testExtractTypeFromStringAnnotation() throws {
        let source = """
        struct TestView: View {
            @State private var name: String = "Test"
            var body: some View { Text("Test") }
        }
        """
        
        let visitor = createVisitor(for: source)
        let stateVars = visitor.stateVariables
        
        #expect(stateVars.count == 1)
        #expect(stateVars.first?.type == "String")
    }
    
    @Test func testExtractTypeFromBoolAnnotation() throws {
        let source = """
        struct TestView: View {
            @State private var isEnabled: Bool = true
            var body: some View { Text("Test") }
        }
        """
        
        let visitor = createVisitor(for: source)
        let stateVars = visitor.stateVariables
        
        #expect(stateVars.count == 1)
        #expect(stateVars.first?.type == "Bool")
    }
    
    @Test func testExtractTypeFromOptionalAnnotation() throws {
        let source = """
        struct TestView: View {
            @State private var optionalValue: String? = nil
            var body: some View { Text("Test") }
        }
        """
        
        let visitor = createVisitor(for: source)
        let stateVars = visitor.stateVariables
        
        #expect(stateVars.count == 1)
        #expect(stateVars.first?.type.contains("String") == true)
    }
    
    // MARK: - Type Inference from Initializers
    
    @Test func testInferTypeFromBooleanLiteral() throws {
        let source = """
        struct TestView: View {
            @State private var isVisible = true
            var body: some View { Text("Test") }
        }
        """
        
        let visitor = createVisitor(for: source)
        let stateVars = visitor.stateVariables
        
        #expect(stateVars.count == 1)
        #expect(stateVars.first?.type == "Bool")
    }
    
    @Test func testInferTypeFromIntegerLiteral() throws {
        let source = """
        struct TestView: View {
            @State private var count = 42
            var body: some View { Text("Test") }
        }
        """
        
        let visitor = createVisitor(for: source)
        let stateVars = visitor.stateVariables
        
        #expect(stateVars.count == 1)
        #expect(stateVars.first?.type == "Int")
    }
    
    @Test func testInferTypeFromFloatLiteral() throws {
        let source = """
        struct TestView: View {
            @State private var value = 3.14
            var body: some View { Text("Test") }
        }
        """
        
        let visitor = createVisitor(for: source)
        let stateVars = visitor.stateVariables
        
        #expect(stateVars.count == 1)
        #expect(stateVars.first?.type == "Double")
    }
    
    @Test func testInferTypeFromStringLiteral() throws {
        let source = """
        struct TestView: View {
            @State private var text = "Hello"
            var body: some View { Text("Test") }
        }
        """
        
        let visitor = createVisitor(for: source)
        let stateVars = visitor.stateVariables
        
        #expect(stateVars.count == 1)
        #expect(stateVars.first?.type == "String")
    }
    
    @Test func testInferTypeFromArrayLiteral() throws {
        let source = """
        struct TestView: View {
            @State private var items = [1, 2, 3]
            var body: some View { Text("Test") }
        }
        """
        
        let visitor = createVisitor(for: source)
        let stateVars = visitor.stateVariables
        
        #expect(stateVars.count == 1)
        #expect(stateVars.first?.type == "Array")
    }
    
    @Test func testInferTypeFromEmptyArray() throws {
        let source = """
        struct TestView: View {
            @State private var items = []
            var body: some View { Text("Test") }
        }
        """
        
        let visitor = createVisitor(for: source)
        let stateVars = visitor.stateVariables
        
        #expect(stateVars.count == 1)
        #expect(stateVars.first?.type == "Array")
    }
    
    @Test func testInferTypeFromFunctionCall() throws {
        let source = """
        struct TestView: View {
            @State private var manager = UserManager()
            var body: some View { Text("Test") }
        }
        """
        
        let visitor = createVisitor(for: source)
        let stateVars = visitor.stateVariables
        
        #expect(stateVars.count == 1)
        #expect(stateVars.first?.type == "UserManager")
    }
    
    @Test func testInferTypeFromCGSize() throws {
        let source = """
        struct TestView: View {
            @State private var size = CGSize(width: 100, height: 200)
            var body: some View { Text("Test") }
        }
        """
        
        let visitor = createVisitor(for: source)
        let stateVars = visitor.stateVariables
        
        #expect(stateVars.count == 1)
        #expect(stateVars.first?.type == "CGSize")
    }
    
    @Test func testInferTypeFromCGPoint() throws {
        let source = """
        struct TestView: View {
            @State private var point = CGPoint.zero
            var body: some View { Text("Test") }
        }
        """
        
        let visitor = createVisitor(for: source)
        let stateVars = visitor.stateVariables
        
        #expect(stateVars.count == 1)
        #expect(stateVars.first?.type == "CGPoint")
    }
    
    @Test func testInferTypeFromColor() throws {
        let source = """
        struct TestView: View {
            @State private var color = Color.blue
            var body: some View { Text("Test") }
        }
        """
        
        let visitor = createVisitor(for: source)
        let stateVars = visitor.stateVariables
        
        #expect(stateVars.count == 1)
        #expect(stateVars.first?.type == "Color")
    }
    
    @Test func testInferTypeFromFont() throws {
        let source = """
        struct TestView: View {
            @State private var font = Font.title
            var body: some View { Text("Test") }
        }
        """
        
        let visitor = createVisitor(for: source)
        let stateVars = visitor.stateVariables
        
        #expect(stateVars.count == 1)
        #expect(stateVars.first?.type == "Font")
    }
    
    @Test func testHandleMissingTypeAnnotationAndInitializer() throws {
        let source = """
        struct TestView: View {
            @State private var value: String
            var body: some View { Text("Test") }
        }
        """
        
        let visitor = createVisitor(for: source)
        let stateVars = visitor.stateVariables
        
        #expect(stateVars.count == 1)
        #expect(stateVars.first?.type == "String")
    }
    
    @Test func testCleanTypeStringRemovesSomeKeyword() throws {
        let source = """
        struct TestView: View {
            @State private var content: some View = Text("Test")
            var body: some View { Text("Test") }
        }
        """
        
        let visitor = createVisitor(for: source)
        let stateVars = visitor.stateVariables
        
        #expect(stateVars.count == 1)
        #expect(stateVars.first?.type == "View")
    }
    
    @Test func testMultipleStateVariables() throws {
        let source = """
        struct TestView: View {
            @State private var count = 0
            @State private var name = "Test"
            @State private var isVisible = true
            var body: some View { Text("Test") }
        }
        """
        
        let visitor = createVisitor(for: source)
        let stateVars = visitor.stateVariables
        
        #expect(stateVars.count == 3)
        #expect(stateVars.contains { $0.type == "Int" && $0.name == "count" })
        #expect(stateVars.contains { $0.type == "String" && $0.name == "name" })
        #expect(stateVars.contains { $0.type == "Bool" && $0.name == "isVisible" })
    }
    
    // MARK: - Other Property Wrapper Tests

    @Test func testExtractStateObjectVariable() throws {
        let source = """
        struct TestView: View {
            @StateObject private var viewModel = ViewModel()
            var body: some View { Text("Test") }
        }
        """

        let visitor = createVisitor(for: source)
        let stateVars = visitor.stateVariables

        #expect(stateVars.count == 1)
        #expect(stateVars.first?.propertyWrapper == .stateObject)
        #expect(stateVars.first?.name == "viewModel")
    }

    @Test func testExtractObservedObjectVariable() throws {
        let source = """
        struct TestView: View {
            @ObservedObject var viewModel: ViewModel
            var body: some View { Text("Test") }
        }
        """

        let visitor = createVisitor(for: source)
        let stateVars = visitor.stateVariables

        #expect(stateVars.count == 1)
        #expect(stateVars.first?.propertyWrapper == .observedObject)
        #expect(stateVars.first?.type == "ViewModel")
    }

    @Test func testExtractEnvironmentObjectVariable() throws {
        let source = """
        struct TestView: View {
            @EnvironmentObject var settings: AppSettings
            var body: some View { Text("Test") }
        }
        """

        let visitor = createVisitor(for: source)
        let stateVars = visitor.stateVariables

        #expect(stateVars.count == 1)
        #expect(stateVars.first?.propertyWrapper == .environmentObject)
        #expect(stateVars.first?.name == "settings")
    }

    @Test func testExtractBindingVariable() throws {
        let source = """
        struct TestView: View {
            @Binding var isEnabled: Bool
            var body: some View { Text("Test") }
        }
        """

        let visitor = createVisitor(for: source)
        let stateVars = visitor.stateVariables

        #expect(stateVars.count == 1)
        #expect(stateVars.first?.propertyWrapper == .binding)
        #expect(stateVars.first?.type == "Bool")
    }

    @Test func testExtractEnvironmentVariable() throws {
        let source = """
        struct TestView: View {
            @Environment(\\.colorScheme) var colorScheme
            var body: some View { Text("Test") }
        }
        """

        let visitor = createVisitor(for: source)
        let stateVars = visitor.stateVariables

        #expect(stateVars.count == 1)
        #expect(stateVars.first?.propertyWrapper == .environment)
        #expect(stateVars.first?.name == "colorScheme")
    }

    @Test func testExtractFocusStateVariable() throws {
        let source = """
        struct TestView: View {
            @FocusState private var isFocused: Bool
            var body: some View { Text("Test") }
        }
        """

        let visitor = createVisitor(for: source)
        let stateVars = visitor.stateVariables

        #expect(stateVars.count == 1)
        #expect(stateVars.first?.propertyWrapper == .focusState)
        #expect(stateVars.first?.name == "isFocused")
    }

    @Test func testExtractAppStorageVariable() throws {
        let source = """
        struct TestView: View {
            @AppStorage("username") var username: String = ""
            var body: some View { Text("Test") }
        }
        """

        let visitor = createVisitor(for: source)
        let stateVars = visitor.stateVariables

        #expect(stateVars.count == 1)
        #expect(stateVars.first?.propertyWrapper == .appStorage)
        #expect(stateVars.first?.type == "String")
    }

    @Test func testExtractSceneStorageVariable() throws {
        let source = """
        struct TestView: View {
            @SceneStorage("draft") var draft: String = ""
            var body: some View { Text("Test") }
        }
        """

        let visitor = createVisitor(for: source)
        let stateVars = visitor.stateVariables

        #expect(stateVars.count == 1)
        #expect(stateVars.first?.propertyWrapper == .sceneStorage)
    }

    @Test func testExtractGestureStateVariable() throws {
        let source = """
        struct TestView: View {
            @GestureState private var dragOffset = CGSize.zero
            var body: some View { Text("Test") }
        }
        """

        let visitor = createVisitor(for: source)
        let stateVars = visitor.stateVariables

        #expect(stateVars.count == 1)
        #expect(stateVars.first?.propertyWrapper == .gestureState)
    }

    @Test func testExtractNamespaceVariable() throws {
        let source = """
        struct TestView: View {
            @Namespace private var animation
            var body: some View { Text("Test") }
        }
        """

        let visitor = createVisitor(for: source)
        let stateVars = visitor.stateVariables

        #expect(stateVars.count == 1)
        #expect(stateVars.first?.propertyWrapper == .namespace)
    }

    @Test func testExtractScaledMetricVariable() throws {
        let source = """
        struct TestView: View {
            @ScaledMetric var size: CGFloat = 100
            var body: some View { Text("Test") }
        }
        """

        let visitor = createVisitor(for: source)
        let stateVars = visitor.stateVariables

        #expect(stateVars.count == 1)
        #expect(stateVars.first?.propertyWrapper == .scaledMetric)
    }

    // MARK: - Mixed Property Wrapper Tests

    @Test func testMultiplePropertyWrapperTypes() throws {
        let source = """
        struct TestView: View {
            @State private var count = 0
            @StateObject private var viewModel = ViewModel()
            @ObservedObject var data: DataModel
            @EnvironmentObject var settings: AppSettings
            @Binding var isEnabled: Bool
            var body: some View { Text("Test") }
        }
        """

        let visitor = createVisitor(for: source)
        let stateVars = visitor.stateVariables

        #expect(stateVars.count == 5)
        #expect(stateVars.contains { $0.propertyWrapper == .state })
        #expect(stateVars.contains { $0.propertyWrapper == .stateObject })
        #expect(stateVars.contains { $0.propertyWrapper == .observedObject })
        #expect(stateVars.contains { $0.propertyWrapper == .environmentObject })
        #expect(stateVars.contains { $0.propertyWrapper == .binding })
    }

    // MARK: - Summary and Filter Methods

    @Test func testGetStateVariableSummary() throws {
        let source = """
        struct TestView: View {
            @State private var a = 0
            @State private var b = 0
            @StateObject private var c = ViewModel()
            @Binding var d: Bool
            var body: some View { Text("Test") }
        }
        """

        let visitor = createVisitor(for: source)
        let summary = visitor.getStateVariableSummary()

        #expect(summary[.state] == 2)
        #expect(summary[.stateObject] == 1)
        #expect(summary[.binding] == 1)
    }

    @Test func testGetStateVariablesWithPropertyWrapper() throws {
        let source = """
        struct TestView: View {
            @State private var a = 0
            @State private var b = 0
            @StateObject private var c = ViewModel()
            var body: some View { Text("Test") }
        }
        """

        let visitor = createVisitor(for: source)
        let stateVars = visitor.getStateVariables(withPropertyWrapper: .state)

        #expect(stateVars.count == 2)
        #expect(stateVars.allSatisfy { $0.propertyWrapper == .state })
    }

    @Test func testGetPotentialEnvironmentObjectCandidates() throws {
        let source = """
        struct TestView: View {
            @State private var count = 0
            @StateObject private var viewModel = ViewModel()
            @ObservedObject var dataModel: DataModel
            var body: some View { Text("Test") }
        }
        """

        let visitor = createVisitor(for: source)
        let candidates = visitor.getPotentialEnvironmentObjectCandidates()

        #expect(candidates.count == 2)
        #expect(candidates.contains { $0.propertyWrapper == .stateObject })
        #expect(candidates.contains { $0.propertyWrapper == .observedObject })
        #expect(!candidates.contains { $0.propertyWrapper == .state })
    }

    // MARK: - Generic Type Tests

    @Test func testExtractGenericArrayType() throws {
        let source = """
        struct TestView: View {
            @State private var items: [String] = []
            var body: some View { Text("Test") }
        }
        """

        let visitor = createVisitor(for: source)
        let stateVars = visitor.stateVariables

        #expect(stateVars.count == 1)
        #expect(stateVars.first?.type.contains("String") == true)
    }

    @Test func testExtractGenericDictionaryType() throws {
        let source = """
        struct TestView: View {
            @State private var cache: [String: Int] = [:]
            var body: some View { Text("Test") }
        }
        """

        let visitor = createVisitor(for: source)
        let stateVars = visitor.stateVariables

        #expect(stateVars.count == 1)
        #expect(stateVars.first?.type.contains("String") == true)
        #expect(stateVars.first?.type.contains("Int") == true)
    }

    @Test func testExtractOptionalGenericType() throws {
        let source = """
        struct TestView: View {
            @State private var selectedItem: Item? = nil
            var body: some View { Text("Test") }
        }
        """

        let visitor = createVisitor(for: source)
        let stateVars = visitor.stateVariables

        #expect(stateVars.count == 1)
        #expect(stateVars.first?.type.contains("Item") == true)
    }

    // MARK: - View Name and File Path Tests

    @Test func testViewNameIsSet() throws {
        let source = """
        struct MyCustomView: View {
            @State private var count = 0
            var body: some View { Text("Test") }
        }
        """

        let syntax = Parser.parse(source: source)
        let visitor = StateVariableVisitor(
            viewName: "MyCustomView",
            filePath: "/custom/path.swift",
            sourceContents: source
        )
        visitor.walk(syntax)

        #expect(visitor.stateVariables.first?.viewName == "MyCustomView")
        #expect(visitor.stateVariables.first?.filePath == "/custom/path.swift")
    }

    @Test func testLineNumberCalculation() throws {
        let source = """
        struct TestView: View {


            @State private var count = 0
            var body: some View { Text("Test") }
        }
        """

        let visitor = createVisitor(for: source)
        let stateVars = visitor.stateVariables

        #expect(stateVars.count == 1)
        #expect(stateVars.first?.lineNumber == 4)
    }

    // MARK: - Edge Cases

    @Test func testNoPropertyWrapperVariablesIgnored() throws {
        let source = """
        struct TestView: View {
            let constant = 42
            var computed: Int { 0 }
            private var regular = "test"
            var body: some View { Text("Test") }
        }
        """

        let visitor = createVisitor(for: source)
        let stateVars = visitor.stateVariables

        #expect(stateVars.isEmpty)
    }

    @Test func testEmptyView() throws {
        let source = """
        struct TestView: View {
            var body: some View { Text("Test") }
        }
        """

        let visitor = createVisitor(for: source)

        #expect(visitor.stateVariables.isEmpty)
        #expect(visitor.getStateVariableSummary().isEmpty)
    }

    // MARK: - Helper Methods

    private func createVisitor(for source: String) -> StateVariableVisitor {
        let syntax = Parser.parse(source: source)
        let viewName = "TestView"
        let filePath = "/test/TestView.swift"
        let visitor = StateVariableVisitor(
            viewName: viewName,
            filePath: filePath,
            sourceContents: source
        )
        visitor.walk(syntax)
        return visitor
    }
} 
