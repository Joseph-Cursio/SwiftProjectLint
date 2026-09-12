@testable import Core
import Foundation
import SwiftParser
import SwiftProjectLintVisitors
import SwiftSyntax
import Testing

/// **A shorthand optional binding shadows whatever the name already was, so it has to be
/// resolved rather than assumed local** (SwiftProjectLint#215).
///
/// Swift 5.7's `if let tagFilter` introduces nothing: it takes its value from whatever `tagFilter`
/// already meant. The collector inserted the name as a local anyway, so when it resolved to a
/// mutable stored property the read of `self` disappeared and the method was seeded as a function
/// of its inputs — in a manifest whose whole contract is that it names pure functions.
///
/// The three arms below are the fixture the issue was filed from. They are the same logic written
/// three ways, and only the first was admitted; the corpus instance was
/// `EditorFormatter.selectedText`, which shorthand-binds a `weak var textView: NSTextView?` — a
/// live view object — and was seeded.
@Suite("Shorthand optional binding resolves rather than shadowing")
struct SelfAccessShorthandBindingTests {

    private func shape(_ source: String, method: String) -> PropertyTestShape? {
        let tree = Parser.parse(source: source)
        let finder = FunctionFinder(viewMode: .sourceAccurate)
        finder.walk(tree)
        guard let declaration = finder.found[method] else { return nil }
        return PropertyTestCandidacy.shape(
            of: declaration,
            knownEquatableTypes: ["String", "Int", "Bool"],
            knownValueTypes: ["Model"]
        )
    }

    // MARK: - The three arms, which must now agree

    /// The defect. `tagFilter` is a mutable stored property and the method is not a function of
    /// its inputs, however the binding is spelled.
    @Test func shorthandBindingOfAMutableStoredPropertyRefutes() {
        let source = """
        struct Model {
            var tagFilter: String?
            func visible(_ tags: String) -> Bool {
                if let tagFilter, !tags.contains(tagFilter) { return false }
                return true
            }
        }
        """
        #expect(shape(source, method: "visible") == nil)
    }

    /// The same logic with the read spelled out. This arm was already correct and is here as the
    /// control: it is what the first arm now agrees with.
    @Test func explicitBindingOfTheSamePropertyStillRefutes() {
        let source = """
        struct Model {
            var tagFilter: String?
            func visible(_ tags: String) -> Bool {
                if let filter = self.tagFilter, !tags.contains(filter) { return false }
                return true
            }
        }
        """
        #expect(shape(source, method: "visible") == nil)
    }

    /// The third spelling, `guard let value = tagFilter`, likewise already correct.
    @Test func guardBindingOfTheSamePropertyStillRefutes() {
        let source = """
        struct Model {
            var tagFilter: String?
            func visible(_ tags: String) -> Bool {
                guard let value = tagFilter else { return true }
                return tags.contains(value)
            }
        }
        """
        #expect(shape(source, method: "visible") == nil)
    }

    // MARK: - What must keep working

    /// **A shorthand binding may legitimately rebind a local, and that is why the rule is
    /// "shadows whatever the name already was" rather than "is never a local".** Here `candidate`
    /// comes from a parameter, so the binding introduces nothing about `self`.
    @Test func shorthandBindingOfALocalIsStillLocal() {
        let source = """
        struct Model {
            func describe(_ text: String) -> String {
                let candidate: String? = text.isEmpty ? nil : text
                if let candidate { return candidate }
                return ""
            }
        }
        """
        #expect(shape(source, method: "describe") == .ofInputs)
    }

    /// A parameter is a local for this purpose too — and a stored property of the same name does
    /// not change that, because the parameter is what the body's name means.
    @Test func shorthandBindingOfAParameterIsStillLocal() {
        let source = """
        struct Model {
            var tagFilter: String?
            func visible(tagFilter: String?, tags: String) -> Bool {
                if let tagFilter, !tags.contains(tagFilter) { return false }
                return true
            }
        }
        """
        #expect(shape(source, method: "visible") == .ofInputs)
    }

    /// **An immutable stored property stays admitted, and this is the half a blunter fix would
    /// have lost.** A first count of the corpus flagged 118 sites by treating every shorthand
    /// binding of a stored-property name as a refutation; spot-checking cut it to 12, because
    /// most of them bind a `let`. Reading one is a read of `self` and is a function of the value,
    /// which is exactly what `.ofSelfAndInputs` means.
    @Test func shorthandBindingOfAnImmutableStoredPropertyIsAdmitted() {
        let source = """
        struct Model {
            let tagFilter: String?
            func visible(_ tags: String) -> Bool {
                if let tagFilter, !tags.contains(tagFilter) { return false }
                return true
            }
        }
        """
        #expect(shape(source, method: "visible") == .ofSelfAndInputs)
    }

    /// A name this file cannot see — a global, or a property declared in another file — resolves
    /// to the refusal, which is the analyzer's stated posture for everything outside the catalog.
    @Test func shorthandBindingOfAnInvisibleNameRefuses() {
        let source = """
        struct Model {
            func visible(_ tags: String) -> Bool {
                if let ambientFilter, !tags.contains(ambientFilter) { return false }
                return true
            }
        }
        """
        #expect(shape(source, method: "visible") == nil)
    }

    final class FunctionFinder: SyntaxVisitor {
        var found: [String: FunctionDeclSyntax] = [:]
        override func visit(_ node: FunctionDeclSyntax) -> SyntaxVisitorContinueKind {
            found[node.name.text] = node
            return .visitChildren
        }
    }
}
