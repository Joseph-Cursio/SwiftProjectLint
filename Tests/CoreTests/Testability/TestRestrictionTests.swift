import Core
import Foundation
import SwiftParser
@testable import SwiftProjectLintModels
@testable import SwiftProjectLintVisitors
import SwiftSyntax
import Testing

/// Why a declaration is unreachable, not just that it is — because the two answers need **different
/// patches**, and the wrong one compiles while changing nothing.
///
/// `@testable import` reaches `internal` and stops. A `private` func is fixed by widening the func.
/// A member nested inside a `private` struct is **not**: the container decides, so widening the
/// member is a no-op. A consumer that acts on `kind: restricted-function` alone cannot tell those
/// apart, and would emit a patch that unblocks nothing — then read the resulting verification
/// failure as evidence against the property.
///
/// `enclosingTypeWinsWhenBothApply` is the load-bearing case: when a declaration is restricted both
/// ways, only the outer restriction binds.
@Suite("Test restriction — what would have to widen")
struct TestRestrictionTests {

    private func firstFunction(_ source: String) -> FunctionDeclSyntax? {
        final class Finder: SyntaxVisitor {
            var found: FunctionDeclSyntax?
            override func visit(_ node: FunctionDeclSyntax) -> SyntaxVisitorContinueKind {
                if found == nil { found = node }
                return .skipChildren
            }
        }
        let finder = Finder(viewMode: .sourceAccurate)
        finder.walk(Parser.parse(source: source))
        return finder.found
    }

    private func restriction(_ source: String) -> TestRestriction? {
        guard let function = firstFunction(source) else {
            Issue.record("no function parsed from fixture")
            return nil
        }
        return PropertyTestCandidacy.restriction(of: function)
    }

    // MARK: - Nothing to widen

    @Test func internalFunctionIsUnrestricted() {
        #expect(restriction("func add(_ a: Int, _ b: Int) -> Int { a + b }") == nil)
    }

    @Test func internalMemberOfInternalTypeIsUnrestricted() {
        #expect(restriction("struct Math { func add(_ a: Int) -> Int { a } }") == nil)
    }

    // MARK: - The declaration is what moves

    @Test func privateFunctionIsRestrictedByItsOwnModifier() {
        #expect(restriction("private func add(_ a: Int) -> Int { a }") == .declaration)
    }

    @Test func fileprivateFunctionIsRestrictedByItsOwnModifier() {
        #expect(restriction("fileprivate func add(_ a: Int) -> Int { a }") == .declaration)
    }

    @Test func privateMemberOfInternalTypeIsRestrictedByItsOwnModifier() {
        #expect(restriction("struct Math { private func add(_ a: Int) -> Int { a } }") == .declaration)
    }

    // MARK: - The enclosing type is what moves

    @Test func internalMemberOfPrivateTypeIsRestrictedByTheContainer() {
        #expect(restriction("private struct Math { func add(_ a: Int) -> Int { a } }") == .enclosingType)
    }

    /// The case the whole distinction exists for. `public` on the member is as loud as an author can
    /// be, and it still cannot be reached — so a patch generator must not read the member's own
    /// modifier and conclude there is nothing to do.
    @Test func publicMemberOfPrivateTypeIsStillRestrictedByTheContainer() {
        #expect(restriction("private struct Math { public func add(_ a: Int) -> Int { a } }")
            == .enclosingType)
    }

    @Test func nestingDepthDoesNotMatter() {
        #expect(restriction("private struct Outer { struct Inner { func add(_ a: Int) -> Int { a } } }")
            == .enclosingType)
    }

    @Test func aPrivateExtensionRestrictsItsMembers() {
        #expect(restriction("private extension Math { func add(_ a: Int) -> Int { a } }")
            == .enclosingType)
    }

    // MARK: - Precedence

    /// **Restricted both ways: only the outer one binds.** Widening the func leaves it unreachable,
    /// so reporting `.declaration` here would send a patch generator to change a keyword that alters
    /// nothing.
    @Test func enclosingTypeWinsWhenBothApply() {
        #expect(restriction("private struct Math { private func add(_ a: Int) -> Int { a } }")
            == .enclosingType)
    }

    // MARK: - The boolean façade still agrees

    /// `isTestReachable` is now derived from `restriction(of:)`, so the two cannot disagree — but
    /// that is worth pinning, since every existing caller still reads the boolean.
    @Test func theBooleanFacadeAgreesWithTheReason() {
        let cases = [
            "func f() -> Int { 1 }",
            "private func f() -> Int { 1 }",
            "private struct S { func f() -> Int { 1 } }",
            "struct S { private func f() -> Int { 1 } }"
        ]
        for source in cases {
            guard let function = firstFunction(source) else { continue }
            let reachable = PropertyTestCandidacy.isTestReachable(function)
            let reason = PropertyTestCandidacy.restriction(of: function)
            #expect(reachable == (reason == nil), "disagreed on: \(source)")
        }
    }

    // MARK: - It reaches the manifest

    @Test func reachabilityCarriesItsRestriction() {
        #expect(TestReachability.unreachable(.enclosingType).restriction == .enclosingType)
        #expect(TestReachability.unreachable(.declaration).restriction == .declaration)
        #expect(TestReachability.reachable.restriction == nil)
        #expect(TestReachability.unknown.restriction == nil)
        #expect(TestReachability.unreachable(.declaration).isUnreachable)
        #expect(!TestReachability.reachable.isUnreachable)
    }

    /// Absent for every kind but `restricted-function`, and omitted from the JSON entirely when
    /// absent — a seed without it stays byte-identical to one written before the field existed.
    @Test func theFieldIsOmittedWhenAbsent() throws {
        let seed = PBTSeed(
            file: "F.swift", line: 1, symbol: "f", rule: "R", kind: .pureFunction
        )
        let encoded = try JSONEncoder().encode(seed)
        let text = try #require(String(data: encoded, encoding: .utf8))
        #expect(!text.contains("restriction"))
    }

    @Test func theFieldRoundTripsWhenPresent() throws {
        let seed = PBTSeed(
            file: "F.swift", line: 1, symbol: "f", rule: "R",
            kind: .restrictedFunction, restriction: .enclosingType
        )
        let decoded = try JSONDecoder().decode(
            PBTSeed.self, from: try JSONEncoder().encode(seed)
        )
        #expect(decoded.restriction == .enclosingType)
    }
}
