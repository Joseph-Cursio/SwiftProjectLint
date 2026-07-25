@testable import Core
import Foundation
import SwiftParser
import SwiftProjectLintVisitors
import SwiftSyntax
import Testing

/// End-to-end cover for the sibling-call gate and the two implicit bindings that used to refute
/// alongside it, exercised through `PropertyTestCandidacy` rather than the analyzer alone.
@Suite
struct SelfAccessSiblingCallTests {

    private func shape(
        _ source: String,
        method: String,
        catalog: CleanInstanceMethodCatalog? = nil
    ) -> PropertyTestShape? {
        let tree = Parser.parse(source: source)
        let finder = FunctionFinder(viewMode: .sourceAccurate)
        finder.walk(tree)
        guard let declaration = finder.found[method] else { return nil }
        return PropertyTestCandidacy.shape(
            of: declaration,
            knownEquatableTypes: ["String", "Int"],
            knownValueTypes: ["Engine"],
            cleanInstanceMethods: catalog ?? CleanInstanceMethodCatalog.build(from: [tree])
        )
    }

    private static let siblingCall = """
    struct Engine {
        func serialize(_ text: String) -> String { decorate(text) }
        func decorate(_ text: String) -> String { text + "!" }
    }
    """

    @Test func aSiblingCallNoLongerRefutesTheCaller() {
        #expect(shape(Self.siblingCall, method: "serialize") == .ofInputs)
    }

    @Test func withoutTheCatalogASiblingCallStillRefutes() {
        // The default catalog is empty, so every existing caller keeps the old answer and the
        // relaxation reaches only code the pre-scan has actually cleared.
        #expect(shape(Self.siblingCall, method: "serialize", catalog: .empty) == nil)
    }

    @Test func aStoredClosurePropertyShadowingTheNameStillRefutes() {
        // `transform(text)` here is a call *through mutable state*, not a method call, and the
        // stored-property lookup has to win over the catalog for it to stay refused.
        let source = """
        struct Engine {
            var transform: (String) -> String = { $0 }
            func serialize(_ text: String) -> String { transform(text) }
        }
        """
        let catalog = CleanInstanceMethodCatalog(methodsByType: ["Engine": ["transform"]])
        #expect(shape(source, method: "serialize", catalog: catalog) == nil)
    }

    @Test func anUnknownCalleeStillRefutes() {
        // Nothing cleared `helper`, so the "every doubt resolves to unresolvedOrMutable" posture
        // still holds outside the catalog.
        let source = """
        struct Engine {
            func serialize(_ text: String) -> String { helper(text) }
        }
        """
        #expect(shape(source, method: "serialize") == nil)
    }

    final class FunctionFinder: SyntaxVisitor {
        var found: [String: FunctionDeclSyntax] = [:]
        override func visit(_ node: FunctionDeclSyntax) -> SyntaxVisitorContinueKind {
            found[node.name.text] = node
            return .visitChildren
        }
    }
}
