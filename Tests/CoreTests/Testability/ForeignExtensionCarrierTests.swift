@testable import Core
import Foundation
import SwiftParser
import SwiftProjectLintVisitors
import SwiftSyntax
import Testing

/// **`extension String` extends a value type, and the analyzer had the answer all along**
/// (SwiftProjectLint#214).
///
/// `enclosingTypeContainer` decided `isValueType` from `knownValueTypes`, which holds *project*
/// declarations — so a stdlib carrier answered "not a value type", and `SelfAccessAnalyzer`'s
/// bare-`self` branch took the reference-type path and refused every member that reads the string
/// it extends. That is not conservatism about something unknown: `String` is a struct.
///
/// Measured before the fix: **0 of 88** parameterless foreign-extension members were seeded across
/// 23 repositories, against 51.4% for extensions on project-declared carriers. The issue
/// recommended documenting rather than fixing, on the grounds that only ~12 of the population were
/// real candidates. Reusing `StdlibTypeNames` recovers **7** of them for one condition, which is
/// what reversed the recommendation.
///
/// The A/B/C fixture below is the issue's own, and its point is causal rather than statistical: A
/// and B differ only in the carrier, A and C only in the relationship to `self`.
@Suite("A foreign extension on a stdlib value type")
struct ForeignExtensionCarrierTests {

    private func shape(_ source: String, method: String) -> PropertyTestShape? {
        let tree = Parser.parse(source: source)
        let finder = FunctionFinder(viewMode: .sourceAccurate)
        finder.walk(tree)
        guard let declaration = finder.found[method] else { return nil }
        return PropertyTestCandidacy.shape(
            of: declaration,
            knownEquatableTypes: ["String", "Int", "Bool"],
            knownValueTypes: ["Markup"]
        )
    }

    // MARK: - The issue's A/B/C fixture

    /// **Arm A.** The same escaping body, on a carrier the project does not declare, reading the
    /// value it extends. This is the arm that was dropped.
    @Test func aMemberOfAStdlibExtensionReadingSelfIsACandidate() {
        let source = """
        extension String {
            func escaped() -> String {
                var out = ""
                for character in self { out.append(character == "<" ? "_" : character) }
                return out
            }
        }
        """
        #expect(shape(source, method: "escaped") == .ofSelfAndInputs)
    }

    /// **Arm B.** The same body on a carrier the project declares. Already correct, and it is what
    /// arm A now agrees with.
    @Test func theSameBodyOnAProjectStructIsACandidate() {
        let source = """
        struct Markup {
            let text: String
            func escaped() -> String {
                var out = ""
                for character in text { out.append(character == "<" ? "_" : character) }
                return out
            }
        }
        """
        #expect(shape(source, method: "escaped") == .ofSelfAndInputs)
    }

    /// **Arm C.** The same carrier, with the input taken as a parameter instead of read from
    /// `self`. Already correct — and before the fix it was the *only* foreign-extension shape that
    /// survived, which is why the corpus measured 0 of 88 for the parameterless ones.
    @Test func aStaticMemberTakingItsInputIsACandidate() {
        let source = """
        extension String {
            static func escaped(_ text: String) -> String {
                var out = ""
                for character in text { out.append(character == "<" ? "_" : character) }
                return out
            }
        }
        """
        #expect(shape(source, method: "escaped") == .ofInputs)
    }

    // MARK: - The conservatism that is kept

    /// A carrier that is neither a project declaration nor a known stdlib value type is still
    /// refused. `NSTextView` is a class, reading `self` reaches a shared object, and nothing in
    /// this change was meant to reach it.
    @Test func anExtensionOnAnUnknownForeignCarrierStillRefuses() {
        let source = """
        extension NSTextView {
            func summary() -> String { describe(self) }
        }
        """
        #expect(shape(source, method: "summary") == nil)
    }

    /// **Only `self` as a whole value is admitted, and the fix is exactly that one condition.**
    /// A member *of* the carrier is still unresolvable — the project declares no stored properties
    /// for `String` — so `self.count` refuses. That is the remaining half of #214's mechanism, and
    /// it is deliberately left in place: admitting an arbitrary member of a foreign type would be
    /// a general relaxation rather than answering a question the analyzer already knew.
    @Test func aMemberReadThroughSelfOnAStdlibCarrierStillRefuses() {
        let source = """
        extension String {
            func widened() -> Int { self.count + 1 }
        }
        """
        #expect(shape(source, method: "widened") == nil)
    }

    // MARK: - Computed properties, which is where most of the recovery landed

    /// `Optional` is a value type too, and `switch self` over it is the corpus's most common shape
    /// of recovery — four of the seven seeds this change restored are computed properties on
    /// `extension Optional where Wrapped == …`.
    ///
    /// Routed through `candidate(of:…)` rather than `shape(of:…)`: a computed property is not a
    /// `FunctionDeclSyntax`, and an earlier version of this test asked the method finder for
    /// `strength`, got nothing, and passed by asserting `nil` — the answer it would have given
    /// before the fix, for a reason unrelated to it.
    @Test func aComputedPropertyOnAnOptionalExtensionIsACandidate() throws {
        let source = """
        extension Optional where Wrapped == Int {
            var strength: Int {
                switch self {
                case let .some(value): return value
                case .none: return 0
                }
            }
        }
        """
        let candidate = try #require(self.candidate(source, property: "strength"))
        #expect(candidate.shape == .ofSelfAndInputs)
    }

    /// The control for the one above, on a carrier that is still unknown.
    @Test func aComputedPropertyOnAnUnknownForeignCarrierStillRefuses() {
        let source = """
        extension NSTextView {
            var summary: String { describe(self) }
        }
        """
        #expect(candidate(source, property: "summary") == nil)
    }

    private func candidate(_ source: String, property: String) -> PropertyTestCandidate? {
        let tree = Parser.parse(source: source)
        let finder = PropertyFinder(viewMode: .sourceAccurate)
        finder.walk(tree)
        guard let declaration = finder.found[property] else { return nil }
        return PropertyTestCandidacy.candidate(
            of: declaration,
            knownEquatableTypes: ["String", "Int", "Bool"],
            knownValueTypes: ["Markup"]
        )
    }

    final class PropertyFinder: SyntaxVisitor {
        var found: [String: VariableDeclSyntax] = [:]
        override func visit(_ node: VariableDeclSyntax) -> SyntaxVisitorContinueKind {
            guard let binding = PropertyTestCandidacy.soleBinding(of: node),
                  let name = binding.pattern.as(IdentifierPatternSyntax.self)?.identifier.text
            else { return .visitChildren }
            found[name] = node
            return .visitChildren
        }
    }

    final class FunctionFinder: SyntaxVisitor {
        var found: [String: FunctionDeclSyntax] = [:]
        override func visit(_ node: FunctionDeclSyntax) -> SyntaxVisitorContinueKind {
            found[node.name.text] = node
            return .visitChildren
        }
    }
}
