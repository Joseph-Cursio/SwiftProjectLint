import Testing
import Foundation
import SwiftSyntax
import SwiftParser
@testable import Core
@testable import SwiftProjectLintRules

/// Tests for type inference from initializer values
@Suite
struct TypeInferenceTests {

    struct TypeInferenceCase: CustomTestStringConvertible, Sendable {
        let declaration: String
        let expectedType: String
        var testDescription: String { "\(declaration) → \(expectedType)" }
    }

    nonisolated static let cases: [TypeInferenceCase] = [
        TypeInferenceCase(declaration: "@State private var isVisible = true", expectedType: "Bool"),
        TypeInferenceCase(declaration: "@State private var count = 42", expectedType: "Int"),
        TypeInferenceCase(declaration: "@State private var value = 3.14", expectedType: "Double"),
        TypeInferenceCase(declaration: "@State private var text = \"Hello\"", expectedType: "String"),
        TypeInferenceCase(declaration: "@State private var items = [1, 2, 3]", expectedType: "Array"),
        TypeInferenceCase(declaration: "@State private var items = []", expectedType: "Array"),
        TypeInferenceCase(declaration: "@State private var manager = UserManager()", expectedType: "UserManager"),
        TypeInferenceCase(
            declaration: "@State private var size = CGSize(width: 100, height: 200)",
            expectedType: "CGSize"
        ),
        TypeInferenceCase(declaration: "@State private var point = CGPoint.zero", expectedType: "CGPoint"),
        TypeInferenceCase(declaration: "@State private var color = Color.blue", expectedType: "Color"),
        TypeInferenceCase(declaration: "@State private var font = Font.title", expectedType: "Font")
    ]

    @Test(arguments: cases)
    func infersType(from testCase: TypeInferenceCase) throws {
        let source = """
        struct TestView: View {
            \(testCase.declaration)
            var body: some View { Text("Test") }
        }
        """

        let visitor = makeStateVariableVisitor(for: source)
        let stateVar = try #require(visitor.stateVariables.first)
        #expect(stateVar.type == testCase.expectedType)
    }

}
