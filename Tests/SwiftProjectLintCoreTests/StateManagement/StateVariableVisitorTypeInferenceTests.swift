import Testing
import Foundation
import SwiftSyntax
import SwiftParser
@testable import SwiftProjectLintCore

/// Tests for type inference from initializer values
@Suite
@MainActor
struct StateVariableVisitorTypeInferenceTests {

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
