import Foundation
import SwiftParser
@testable import SwiftProjectLintRules
import SwiftSyntax
import Testing

/// The suggestion is only worth printing when it describes the **whole**
/// comparator. Half of these tests are cases where it must stay silent, because
/// a name a reader has to verify costs what inventing one would have.
@Suite("ComparatorName — derived from the keys compared")
struct ComparatorNameTests {

    private func closure(
        _ body: String, signature: String = "lhs, rhs in "
    ) throws -> ClosureExprSyntax {
        let tree = Parser.parse(source: "let _ = xs.sorted { \(signature)\(body) }")
        final class Finder: SyntaxVisitor {
            var found: ClosureExprSyntax?
            override func visit(_ node: ClosureExprSyntax) -> SyntaxVisitorContinueKind {
                if found == nil { found = node }
                return .skipChildren
            }
        }
        let finder = Finder(viewMode: .sourceAccurate)
        finder.walk(tree)
        return try #require(finder.found)
    }

    /// The shorthand spelling, which the corpus uses far more than named
    /// parameters. It must be parsed *without* a signature — wrapping a `$0`
    /// body in `{ lhs, rhs in … }` makes every key unresolvable, which silently
    /// turns a silence test into a test of nothing.
    private func shorthandClosure(_ body: String) throws -> ClosureExprSyntax {
        try closure(body, signature: "")
    }

    // MARK: - The shapes it should name

    @Test("a tuple comparison is a multi-key comparator and is named as one")
    func tupleTwoKeys() throws {
        let sut = try shorthandClosure("return ($0.name, $0.parameterCount) < ($1.name, $1.parameterCount)")
        #expect(ComparatorName.derived(from: sut) == "byNameThenParameterCount")
    }

    @Test("tuple elements may be nested, and there may be more than two")
    func tupleThreeNestedKeys() throws {
        let sut = try closure("""
            return (lhs.location.file, lhs.location.line, lhs.typeName)
                 < (rhs.location.file, rhs.location.line, rhs.typeName)
            """)
        #expect(ComparatorName.derived(from: sut)
                == "byLocationFileThenLocationLineThenTypeName")
    }

    /// Taken verbatim from `CensusRenderer`. Only the *second* element is
    /// swapped, so this orders by value descending and key ascending under a
    /// single `>`. Reading the direction off the operator once would name it
    /// `byValueDescendingThenKeyDescending` — confident and wrong.
    @Test("a swapped tuple element reverses that key alone")
    func swappedTupleElement() throws {
        let sut = try shorthandClosure("return ($0.value, $1.key) > ($1.value, $0.key)")
        #expect(ComparatorName.derived(from: sut) == "byValueDescendingThenKey")
    }


    /// Every multi-key comparator this rule found silent on the real corpus was
    /// silent for one reason: a nested key. Because a single unaccounted clause
    /// silences the whole closure, one `identity.normalized` cost the entire name.
    @Test("a nested key is named by its whole path, not its last component")
    func nestedKeyPath() throws {
        let sut = try closure("""
            if lhs.score != rhs.score { return lhs.score > rhs.score }
            return lhs.identity.normalized < rhs.identity.normalized
            """)
        #expect(ComparatorName.derived(from: sut) == "byScoreDescendingThenIdentityNormalized")
    }

    @Test("both keys may be nested")
    func twoNestedKeys() throws {
        let sut = try closure("""
            if lhs.members.count != rhs.members.count { return lhs.members.count > rhs.members.count }
            return lhs.shape.canonicalLabelKey < rhs.shape.canonicalLabelKey
            """)
        #expect(ComparatorName.derived(from: sut) == "byMembersCountDescendingThenShapeCanonicalLabelKey")
    }


    @Test("a guard-style tiebreak names both keys in order")
    func guardStyleTwoKeys() throws {
        let sut = try closure("""
            if lhs.location != rhs.location { return lhs.location < rhs.location }
            return lhs.typeName < rhs.typeName
            """)
        #expect(ComparatorName.derived(from: sut) == "byLocationThenTypeName")
    }

    @Test("a descending primary is named as such")
    func descendingPrimary() throws {
        let sut = try closure("""
            if lhs.total != rhs.total { return lhs.total > rhs.total }
            return lhs.template < rhs.template
            """)
        #expect(ComparatorName.derived(from: sut) == "byTotalDescendingThenTemplate")
    }

    @Test("the ternary spelling names the same keys as the guard spelling")
    func ternarySpelling() throws {
        let sut = try closure(
            "lhs.value != rhs.value ? lhs.value > rhs.value : lhs.key < rhs.key")
        #expect(ComparatorName.derived(from: sut) == "byValueDescendingThenKey")
    }

    @Test("three keys are all named, in source order")
    func threeKeys() throws {
        let sut = try closure("""
            if lhs.file != rhs.file { return lhs.file < rhs.file }
            if lhs.line != rhs.line { return lhs.line < rhs.line }
            return lhs.column < rhs.column
            """)
        #expect(ComparatorName.derived(from: sut) == "byFileThenLineThenColumn")
    }

    // MARK: - The shapes it must decline

    /// **Not a limitation.** A single ascending key inherits its law from the
    /// field's own `Comparable` conformance and cannot violate it, and
    /// `ascendingByKey` says nothing `$0.key < $1.key` did not.
    @Test("a single key gets no name")
    func singleKeyIsSilent() throws {
        #expect(ComparatorName.derived(from: try closure("return lhs.key < rhs.key")) == nil)
    }

    /// This case used to assert silence, under the heading "a computed key gets
    /// no name". That heading was wrong twice over. The code never tested
    /// computedness — it cannot, from syntax — and `byNameCount` is precisely the
    /// name a reader would have written, so withholding it helped nobody. What
    /// the old test actually pinned was a limitation of the deriver, phrased as
    /// though it were a principle.
    @Test("a computed key is named like any other — computedness is not visible to syntax")
    func computedKeyIsNamed() throws {
        let sut = try closure("""
            if lhs.name.count != rhs.name.count { return lhs.name.count < rhs.name.count }
            return lhs.id < rhs.id
            """)
        #expect(ComparatorName.derived(from: sut) == "byNameCountThenId")
    }

    /// The boundary that does hold, and unlike computedness is decidable from
    /// syntax: a key reached through a **call** is not named. The call may be
    /// costly, may not be a projection of the value at all, and its name reads as
    /// an action rather than a key.
    @Test("a key reached through a call gets no name")
    func calledKeyIsSilent() throws {
        let sut = try closure("""
            if lhs.name.trimmed() != rhs.name.trimmed() { return lhs.name.trimmed() < rhs.name.trimmed() }
            return lhs.id < rhs.id
            """)
        #expect(ComparatorName.derived(from: sut) == nil)
    }

    @Test("a subscripted key gets no name")
    func subscriptedKeyIsSilent() throws {
        let sut = try closure("""
            if lhs.tags[0] != rhs.tags[0] { return lhs.tags[0] < rhs.tags[0] }
            return lhs.id < rhs.id
            """)
        #expect(ComparatorName.derived(from: sut) == nil)
    }

    @Test("an unrecognised operator gets no name")
    func unrecognisedOperatorIsSilent() throws {
        let sut = try closure("""
            if lhs.rank ~= rhs.rank { return lhs.rank < rhs.rank }
            return lhs.id < rhs.id
            """)
        #expect(ComparatorName.derived(from: sut) == nil)
    }

    /// The two sides must be the *same* property on the two parameters. A
    /// comparator relating different fields is doing something a two-key name
    /// would misdescribe.
    @Test("comparing different properties gets no name")
    func crossPropertyIsSilent() throws {
        let sut = try closure("""
            if lhs.start != rhs.end { return lhs.start < rhs.end }
            return lhs.id < rhs.id
            """)
        #expect(ComparatorName.derived(from: sut) == nil)
    }

    /// A tuple position orders perfectly well — this comparator is correct — but
    /// `by1TimestampThen0` is not a name anyone would have written, so the rule
    /// says nothing rather than something a reader has to undo.
    @Test("a tuple-position key stays silent even though it orders")
    func tuplePositionKey() throws {
        let sut = try closure("""
            if lhs.1.timestamp != rhs.1.timestamp { return lhs.1.timestamp < rhs.1.timestamp }
            return lhs.0 < rhs.0
            """)
        #expect(ComparatorName.derived(from: sut) == nil)
    }

    @Test("a tuple element reached through a call gets no name")
    func tupleWithCallElement() throws {
        let sut = try shorthandClosure("return (origin($0), $0.typeName) < (origin($1), $1.typeName)")
        #expect(ComparatorName.derived(from: sut) == nil)
    }

    /// A name covering part of a tuple covers none of the comparator, so one
    /// unreadable element silences the whole thing rather than naming the rest.
    @Test("one unreadable tuple element silences the whole comparator")
    func tupleWithSubscriptElement() throws {
        let sut = try shorthandClosure("return ($0.name, tierRank[$0.tier] ?? 0) < ($1.name, tierRank[$1.tier] ?? 0)")
        #expect(ComparatorName.derived(from: sut) == nil)
    }

    /// A parenthesised single key is still a single key — the parentheses are a
    /// one-element tuple to the parser, and must not make it look multi-key.
    @Test("a parenthesised single key stays silent")
    func parenthesisedSingleKey() throws {
        #expect(ComparatorName.derived(from: try shorthandClosure("return ($0.name) < ($1.name)")) == nil)
    }
}
