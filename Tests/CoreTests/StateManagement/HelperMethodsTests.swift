import Testing
import Foundation
import SwiftSyntax
import SwiftParser
@testable import Core

/// Tests for StateVariableVisitor helper methods and edge cases
@Suite
struct HelperMethodsTests {

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
        #expect(candidates.contains { $0.propertyWrapper == .state } == false)

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
        let stateVar = try #require(visitor.stateVariables.first)
        #expect(stateVar.type.contains("String"))
    }

    @Test func testExtractGenericDictionaryType() throws {
        let source = """
        struct TestView: View {
            @State private var cache: [String: Int] = [:]
            var body: some View { Text("Test") }
        }
        """

        let visitor = createVisitor(for: source)
        let stateVar = try #require(visitor.stateVariables.first)
        #expect(stateVar.type.contains("String"))
        #expect(stateVar.type.contains("Int"))
    }

    @Test func testExtractOptionalGenericType() throws {
        let source = """
        struct TestView: View {
            @State private var selectedItem: Item? = nil
            var body: some View { Text("Test") }
        }
        """

        let visitor = createVisitor(for: source)
        let stateVar = try #require(visitor.stateVariables.first)
        #expect(stateVar.type.contains("Item"))
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

        let stateVar = try #require(visitor.stateVariables.first)
        #expect(stateVar.viewName == "MyCustomView")
        #expect(stateVar.filePath == "/custom/path.swift")
    }

    @Test func testLineNumberCalculation() throws {
        let source = """
        struct TestView: View {


            @State private var count = 0
            var body: some View { Text("Test") }
        }
        """

        let visitor = createVisitor(for: source)
        let stateVar = try #require(visitor.stateVariables.first)
        #expect(stateVar.lineNumber == 4)
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
        #expect(visitor.stateVariables.isEmpty)
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
