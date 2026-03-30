import Testing
import Foundation
import SwiftSyntax
import SwiftParser
@testable import Core
@testable import SwiftProjectLintRules

/// Tests for type extraction from explicit type annotations
@Suite
struct TypeExtractionTests {

    struct TypeExtractionCase: CustomTestStringConvertible, Sendable {
        let declaration: String
        let expectedType: String
        let expectedName: String?
        let typeMatchMode: TypeMatchMode
        var testDescription: String { declaration }

        enum TypeMatchMode: Sendable {
            case exact
            case contains
        }

        init(_ declaration: String, type expectedType: String, name: String? = nil, match: TypeMatchMode = .exact) {
            self.declaration = declaration
            self.expectedType = expectedType
            self.expectedName = name
            self.typeMatchMode = match
        }
    }

    nonisolated static let cases: [TypeExtractionCase] = [
        TypeExtractionCase("@State private var count: Int = 0", type: "Int", name: "count"),
        TypeExtractionCase("@State private var name: String = \"Test\"", type: "String"),
        TypeExtractionCase("@State private var isEnabled: Bool = true", type: "Bool"),
        TypeExtractionCase("@State private var optionalValue: String? = nil", type: "String", match: .contains),
        TypeExtractionCase("@State private var content: some View = Text(\"Test\")", type: "View"),
        TypeExtractionCase("@State private var value: String", type: "String")
    ]

    @Test(arguments: cases)
    func extractsType(from testCase: TypeExtractionCase) throws {
        let source = """
        struct TestView: View {
            \(testCase.declaration)
            var body: some View { Text("Test") }
        }
        """

        let visitor = makeStateVariableVisitor(for: source)
        let stateVar = try #require(visitor.stateVariables.first)

        switch testCase.typeMatchMode {
        case .exact:
            #expect(stateVar.type == testCase.expectedType)
        case .contains:
            #expect(stateVar.type.contains(testCase.expectedType))
        }

        if let expectedName = testCase.expectedName {
            #expect(stateVar.name == expectedName)
        }
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
