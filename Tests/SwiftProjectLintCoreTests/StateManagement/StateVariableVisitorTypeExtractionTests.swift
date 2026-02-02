import Testing
import Foundation
import SwiftSyntax
import SwiftParser
@testable import SwiftProjectLintCore

/// Tests for type extraction from explicit type annotations
@Suite
@MainActor
struct StateVariableVisitorTypeExtractionTests {

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
