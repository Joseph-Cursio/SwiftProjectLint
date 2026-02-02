import Testing
import Foundation
import SwiftSyntax
import SwiftParser
@testable import SwiftProjectLintCore

/// Tests for different property wrapper types detection
@Suite
@MainActor
struct StateVariableVisitorPropertyWrapperTests {

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

    // MARK: - Helper Methods

    private func createVisitor(for source: String) -> StateVariableVisitor {
        let syntax = Parser.parse(source: source)
        let visitor = StateVariableVisitor(
            viewName: "TestView",
            filePath: "/test/TestView.swift",
            sourceContents: source
        )
        visitor.walk(syntax)
        return visitor
    }
}
