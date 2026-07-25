@testable import Core
import Foundation
import SwiftParser
import SwiftProjectLintVisitors
import SwiftSyntax
import Testing

/// Names bound implicitly — by an untyped `catch`, or by closure shorthand — are declared nowhere a
/// pattern collector can see, so they used to reach the analyzer's "assume the dangerous one"
/// branch and refute any method that used one.
@Suite
struct SelfAccessImplicitBindingTests {

    private func shape(_ source: String, method: String) -> PropertyTestShape? {
        let tree = Parser.parse(source: source)
        let finder = FunctionFinder(viewMode: .sourceAccurate)
        finder.walk(tree)
        guard let declaration = finder.found[method] else { return nil }
        return PropertyTestCandidacy.shape(
            of: declaration,
            knownEquatableTypes: ["String", "Int"],
            knownValueTypes: ["Engine"]
        )
    }

    @Test func anUntypedCatchBindingNoLongerRefutes() {
        let source = """
        struct Engine {
            func describe(_ text: String) -> String {
                do {
                    return text.uppercased()
                } catch {
                    return error.localizedDescription
                }
            }
        }
        """
        #expect(shape(source, method: "describe") == .ofInputs)
    }

    @Test func aStoredPropertyNamedErrorOutsideACatchStillRefutes() {
        // The catch binding is resolved by scope, not by adding `error` to the method's locals, so
        // a genuine stored `error` is still instance state.
        let source = """
        struct Engine {
            var error: String = ""
            func describe(_ text: String) -> String { text + error }
        }
        """
        #expect(shape(source, method: "describe") == nil)
    }

    @Test func shorthandClosureParametersNoLongerRefute() {
        let source = """
        struct Engine {
            func pick(_ items: [String]) -> String {
                items.filter { $0.count > 2 }.joined()
            }
        }
        """
        #expect(shape(source, method: "pick") == .ofInputs)
    }

    final class FunctionFinder: SyntaxVisitor {
        var found: [String: FunctionDeclSyntax] = [:]
        override func visit(_ node: FunctionDeclSyntax) -> SyntaxVisitorContinueKind {
            found[node.name.text] = node
            return .visitChildren
        }
    }
}
