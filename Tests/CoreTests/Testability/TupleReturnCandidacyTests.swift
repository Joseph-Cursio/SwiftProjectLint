@testable import Core
import SwiftParser
import SwiftProjectLintModels
@testable import SwiftProjectLintRules
@testable import SwiftProjectLintVisitors
import SwiftSyntax
import Testing

/// **A tuple of `Equatable` values is something a test can compare, and the gate said it was not.**
///
/// A candidate must return something a test can assert on with `==`. The check looked the return
/// type's *nominal base* up in the known-`Equatable` names, and a tuple has no nominal base — so
/// `-> (text: String, didTruncate: Bool)` was refused. The `Equatable` gate dropped tuples with
/// closures on exactly those grounds (a4427b8c), which is true of the lookup and not of `==`. The
/// motivating case is SwiftAssist's `String.prefix(utf8Bytes:)`, whose two-field result is exactly
/// what a byte-budget law states.
///
/// The rule is the standard library's own. `==` is overloaded for tuples of **two to six**
/// `Equatable` elements and for nothing wider, and a tuple never conforms to `Equatable` itself — so
/// an Optional, an Array or a nested tuple *of* a tuple has no `==` and stays refused. A
/// parenthesized type is not a tuple at all: `(Int)` is `Int`.
///
/// What this does **not** do is seed `prefix(utf8Bytes:)`. Its body reads `isEmpty` and `utf8`
/// without `self.`, and `SelfAccessAnalyzer` refuses a member of a carrier the project does not
/// declare — the half of #214 that was kept on purpose. The control test pins that: the
/// tuple gate passes, and the candidate is still refused, for the other reason.
@Suite("A tuple return is something a test can assert on")
struct TupleReturnCandidacyTests {

    /// Spellings a test can compare with `==`.
    static let admitted = [
        "(Int, Int)",
        "(text: String, didTruncate: Bool)",
        "(Int, String?, [Bool])",
        "(Int, Int, Int, Int, Int, Int)",
        "((Int, Int))",
        "((Int), String)",
        "(Int)"
    ]

    /// Spellings with no `==`, each for a reason the stdlib states.
    static let refused = [
        "()",
        "Void",
        "(())",
        "(Int, ())",
        "(Int, Void)",
        "(Int, Int, Int, Int, Int, Int, Int)",
        "((Int, Int), String)",
        "(Int, Int)?",
        "(Int, Int)!",
        "[(Int, Int)]",
        "Optional<(Int, Int)>",
        "(Int, any Error)",
        "(Int, () -> Int)",
        "(Int, Widget)",
        "(Int...)",
        "(Int) -> (Int, Int)"
    ]

    // MARK: - The gate

    @Test(arguments: admitted)
    func aTupleOfEquatableElementsIsAssertable(spelling: String) throws {
        #expect(try returnVerdict(spelling))
    }

    @Test(arguments: refused)
    func aSpellingWithNoEqualityIsRefused(spelling: String) throws {
        #expect(try returnVerdict(spelling) == false)
    }

    /// The overloads ask only `Element: Equatable`, and the conformance index holds exactly the
    /// project types that are — so a project type counts as an element as it counts as a return.
    @Test func aProjectEquatableElementCounts() throws {
        #expect(try returnVerdict("(Widget, Int)", knownEquatableTypes: ["Widget"]))
        #expect(try returnVerdict("(Widget, Int)") == false)
    }

    /// `Self` resolves per element, exactly as it does for a whole `-> Self` return (B26).
    @Test func aSelfElementResolvesToTheEnclosingType() throws {
        #expect(try returnVerdict("(Self, Bool)", enclosingTypeName: "Ring", knownEquatableTypes: ["Ring"]))
        #expect(try returnVerdict("(Self, Bool)", enclosingTypeName: "Ring") == false)
    }

    /// **Not a decision of the tuple rule — an imprecision it inherits.** A dictionary resolves to
    /// the name `Dictionary` and its value type is never looked at, so `[String: Widget]` passes for
    /// a non-`Equatable` `Widget`, and `[String: (Int, Int)]` passes although it has no `==`. It was
    /// admitted before tuples were and still is. Pinned so the rule page's statement of it stays
    /// true; checking a container's arguments would narrow the gate and needs its own measurement.
    @Test func aDictionaryValueIsNotLookedInto() throws {
        #expect(try returnVerdict("[String: (Int, Int)]"))
    }

    /// The function and computed-property paths used to carry byte-identical copies of the check.
    /// They now share one, and this keeps it that way: every spelling gets one verdict.
    @Test(arguments: admitted + refused)
    func theComputedPropertyPathAgrees(spelling: String) throws {
        let returnType = try #require(signature(returning: spelling).returnClause?.type)
        let propertyVerdict = PropertyTestCandidacy.typeIsAssertable(
            returnType,
            enclosingTypeName: nil,
            knownEquatableTypes: []
        )
        #expect(try propertyVerdict == returnVerdict(spelling))
    }

    // MARK: - Through the candidacy predicate

    /// A stdlib carrier and a tuple return together: `self` is the string, the tuple is the answer.
    @Test func aTupleReturningMemberOfAStdlibExtensionIsACandidate() {
        let source = """
        extension String {
            func tagged(_ n: Int) -> (text: String, count: Int) { (self, n) }
        }
        """
        #expect(shape(source, method: "tagged") == .ofSelfAndInputs)
    }

    /// **The control: the tuple gate is no longer the reason.** SwiftAssist's
    /// `String.prefix(utf8Bytes:)`, verbatim. Its return now passes — and it is still not a
    /// candidate, because `isEmpty` and `utf8` are members of `self` read without `self.`, and
    /// `SelfAccessAnalyzer` refuses a member the project declares no stored property for
    /// (`resolveSelfProperty`; the kept half of #214, `ForeignExtensionCarrierTests`). Seeding it
    /// needs that policy changed, which this change deliberately does not do.
    @Test func prefixUTF8BytesPassesTheTupleGateAndIsStillRefused() throws {
        let declaration = try #require(function(named: "prefix", in: Self.prefixUTF8Bytes))
        #expect(PropertyTestCandidacy.returnIsAssertable(
            declaration.signature,
            enclosingTypeName: "String",
            knownEquatableTypes: []
        ))
        #expect(shape(Self.prefixUTF8Bytes, method: "prefix") == nil)
    }

    /// The other arm of the control. The same logic reading the string through a local copy — a
    /// read of a value, which the analyzer already admits — is a candidate. So the implicit member
    /// reads are the whole of what still stands between `prefix(utf8Bytes:)` and a seed.
    @Test func theSameLogicThroughALocalCopyIsACandidate() {
        let source = """
        extension String {
            public func prefix(utf8Bytes limit: Int) -> (text: String, didTruncate: Bool) {
                let whole = self
                guard limit > 0 else { return ("", !whole.isEmpty) }
                guard whole.utf8.count > limit else { return (whole, false) }

                var result = ""
                var used = 0
                for character in whole {
                    let width = String(character).utf8.count
                    guard used + width <= limit else { break }
                    result.append(character)
                    used += width
                }
                return (result, true)
            }
        }
        """
        #expect(shape(source, method: "prefix") == .ofSelfAndInputs)
    }

    /// SwiftAssist `Sources/SwiftAssist/Agent/Tools/ReadWindow.swift`, as of 52823df.
    private static let prefixUTF8Bytes = """
    extension String {
        public func prefix(utf8Bytes limit: Int) -> (text: String, didTruncate: Bool) {
            guard limit > 0 else { return ("", !isEmpty) }
            guard utf8.count > limit else { return (self, false) }

            var result = ""
            var used = 0
            for character in self {
                let width = String(character).utf8.count
                guard used + width <= limit else { break }
                result.append(character)
                used += width
            }
            return (result, true)
        }
    }
    """

    // MARK: - Through the seeding rule

    @Test func aLabelledTupleReturnIsSeededAsPureAndTotal() throws {
        let issue = try #require(findings("""
        func minMax(_ a: Int, _ b: Int) -> (min: Int, max: Int) { a < b ? (a, b) : (b, a) }
        """).first)
        #expect(issue.message.contains("minMax"))
        #expect(issue.message.contains("pure and total"))
        #expect(issue.message.contains("partial") == false)
        // Two same-typed inputs and a tuple out is no role the signature entails.
        #expect(issue.role == nil)
    }

    /// An Optional of a tuple has no `==`: `Optional` is `Equatable` only when its wrapped type is.
    @Test func anOptionalTupleReturnIsNotSeeded() {
        #expect(findings("func split(_ s: String) -> (String, String)? { nil }").isEmpty)
    }

    @Test func aTupleElementMustBeKnownEquatable() {
        let source = "func tag(_ x: Int) -> (Int, Widget) { (x, Widget(x)) }"
        #expect(findings(source).isEmpty)
        #expect(findings(source, equatableTypes: ["Widget"]).count == 1)
    }

    /// **A throwing tuple candidate is told to unwrap, not to compare the `try?` results.** The
    /// advice every other throwing candidate gets — compare `try? f(…)` on both sides — does not
    /// compile here: the two sides are Optionals of a tuple, and an Optional has `==` only when its
    /// wrapped type is `Equatable`, which a tuple never is. Checked against Swift 6.4.
    @Test func aThrowingTupleCandidateIsToldToUnwrapBothResults() throws {
        let issue = try #require(findings("""
        func parsePair(_ s: String) throws -> (Int, Int) {
            guard let value = Int(s) else { throw ParseError.bad }
            return (value, value)
        }
        """).first)
        #expect(issue.message.contains("pure but partial"))
        let suggestion = try #require(issue.suggestion)
        #expect(suggestion.contains("if let"))
        #expect(suggestion.contains("compare `try? parsePair(…)` on both sides") == false)
    }

    /// The `(T) -> T` normalizer guess is read off the signature text, so it now reaches a tuple
    /// endomorphism too. It is a conjecture rather than an entailed law, as it is for scalars.
    @Test func aTupleEndomorphismCarriesTheNormalizerGuess() throws {
        let issue = try #require(findings("func swapped(_ p: (Int, Int)) -> (Int, Int) { (p.1, p.0) }").first)
        #expect(issue.role == .normalizer)
    }

    // MARK: - Drivers

    private func signature(returning spelling: String) throws -> FunctionSignatureSyntax {
        let declaration = try #require(function(named: "f", in: "func f() -> \(spelling) { fatalError() }"))
        return declaration.signature
    }

    /// The function path's verdict on `spelling` as a whole return type.
    private func returnVerdict(
        _ spelling: String,
        enclosingTypeName: String? = nil,
        knownEquatableTypes: Set<String> = []
    ) throws -> Bool {
        let signature = try signature(returning: spelling)
        return PropertyTestCandidacy.returnIsAssertable(
            signature,
            enclosingTypeName: enclosingTypeName,
            knownEquatableTypes: knownEquatableTypes
        )
    }

    private func shape(_ source: String, method: String) -> PropertyTestShape? {
        guard let declaration = function(named: method, in: source) else { return nil }
        return PropertyTestCandidacy.shape(of: declaration, knownEquatableTypes: [])
    }

    private func function(named name: String, in source: String) -> FunctionDeclSyntax? {
        let finder = FunctionFinder(viewMode: .sourceAccurate)
        finder.walk(Parser.parse(source: source))
        return finder.found[name]
    }

    /// The sibling suites' drivers are file-scope private, so this suite carries its own.
    private func findings(_ source: String, equatableTypes: Set<String> = []) -> [LintIssue] {
        let visitor = PureFunctionCandidateVisitor(patternCategory: .testability)
        visitor.knownEquatableTypes = equatableTypes
        let syntax = Parser.parse(source: source)
        visitor.setSourceLocationConverter(SourceLocationConverter(fileName: "Logic.swift", tree: syntax))
        visitor.setFilePath("Logic.swift")
        visitor.walk(syntax)
        return visitor.detectedIssues.filter { $0.ruleName == .pureFunctionCandidate }
    }

    final class FunctionFinder: SyntaxVisitor {
        var found: [String: FunctionDeclSyntax] = [:]
        override func visit(_ node: FunctionDeclSyntax) -> SyntaxVisitorContinueKind {
            found[node.name.text] = node
            return .visitChildren
        }
    }
}
