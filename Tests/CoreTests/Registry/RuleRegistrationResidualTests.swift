@testable import Core
import Testing

/// Every declared rule must be reachable by the engine, and every exception must say why.
///
/// Nothing checked this, and the arithmetic people reach for gives the wrong answer. Counting the
/// enum against `SwiftProjectLintRules` yields "10 declared but never registered", which is false
/// twice over: it misses the sibling `SwiftProjectLintIdempotencyRules` package, and it misses the
/// `ruleName:` emission path used where one visitor raises two findings. A downstream document
/// carried that wrong conclusion as a live finding until someone scanned by hand (issue #73).
///
/// **Asserted against the live registry rather than by scanning source text.** A grep for
/// `name: .foo` answers "is this identifier mentioned somewhere", which is not the question — an
/// identifier can be mentioned in a registrar that is never wired into a category, and would then
/// pass a textual check while reaching no analysis. `PatternRegistryFactory.createConfiguredSystem()`
/// builds the same registry the CLI uses, so what it contains is what the engine can actually run.
@Suite("Registry — every declared rule is reachable")
struct RuleRegistrationResidualTests {

    /// Rules the engine can run: one registered pattern each.
    private static var registeredRules: Set<RuleIdentifier> {
        let system = PatternRegistryFactory.createConfiguredSystem()
        return Set(system.detector.registry.getAllPatterns().map(\.name))
    }

    /// Declared rules that are deliberately *not* registered patterns, and the reason for each.
    ///
    /// The list is the point of this test. An identifier missing from the registry is either a
    /// rule that silently reaches nothing — a real defect — or a deliberate arrangement someone
    /// has to have thought about. Writing the reason down is what tells the next reader which.
    /// Empty, and worth keeping that way.
    ///
    /// It held one entry — `.onTapGestureMissingAccessibility`, emitted with `ruleName:` by a
    /// visitor registered under a different name. Writing the reason down is what exposed it as a
    /// defect rather than an arrangement: a rule with no pattern is filtered out of its own
    /// visitor's output by `SourcePatternDetector.runVisitors`, so it never fired on a default run.
    /// It now has a pattern, and `testNoExceptionIsActuallyRegistered` is what forced this entry to
    /// be removed rather than left behind as a stale excuse.
    private static let unregisteredByDesign: [RuleIdentifier: String] = [:]

    @Test("every selectable rule is registered, or documented as to why not")
    func testEverySelectableRuleIsReachable() {
        let unreachable = RuleIdentifier.selectableRules
            .subtracting(Self.registeredRules)
            .subtracting(Self.unregisteredByDesign.keys)

        let names = unreachable.map(\.rawValue).sorted()
        #expect(
            unreachable.isEmpty,
            "declared but registered nowhere — wire it up, or record why not: \(names)"
        )
    }

    /// The reverse direction, which is the one that rots quietly.
    ///
    /// If a rule on the exception list later gains a registered pattern, the entry becomes a lie
    /// that still passes the test above. Failing here forces it to be removed.
    @Test("no exception is stale")
    func testNoExceptionIsActuallyRegistered() {
        let registered = Self.registeredRules
        let stale = Self.unregisteredByDesign.keys.filter { registered.contains($0) }

        #expect(
            stale.isEmpty,
            "now registered — drop from unregisteredByDesign: \(stale.map(\.rawValue).sorted())"
        )
    }

    /// The sentinels are not rules and must never acquire a pattern.
    ///
    /// `unknown` is used as a placeholder `name:` by several multi-purpose visitors, so it is
    /// genuinely written in registrar-adjacent code — which is exactly why a textual check would
    /// have counted it as registered. It must not reach the registry.
    @Test("no sentinel is registered as a rule")
    func testSentinelsAreNotRegistered() {
        let registered = RuleIdentifier.sentinels.intersection(Self.registeredRules)

        #expect(
            registered.isEmpty,
            "sentinels are not rules: \(registered.map(\.rawValue).sorted())"
        )
    }

    /// Guards the count the README states from the other side.
    ///
    /// `READMERuleCountTests` pins the prose to `selectableRules`; this pins `selectableRules` to
    /// what the engine will actually run. Together they mean the advertised number cannot drift
    /// from the shipped behaviour in either direction.
    /// Compared as two small difference sets rather than `accounted == selectableRules`, because
    /// the equality form prints both 200-element sets on failure and the difference is the only
    /// part anyone reads.
    @Test("the registry accounts for every selectable rule exactly once")
    func testRegistryAccountsForEveryRule() {
        let accounted = Self.registeredRules.union(Self.unregisteredByDesign.keys)
        let unaccounted = RuleIdentifier.selectableRules.subtracting(accounted)
        let unexpected = accounted.subtracting(RuleIdentifier.selectableRules)

        #expect(unaccounted.isEmpty, "no pattern and no recorded reason: \(names(unaccounted))")
        #expect(unexpected.isEmpty, "accounted for but not a selectable rule: \(names(unexpected))")
    }

    private func names(_ rules: Set<RuleIdentifier>) -> [String] {
        rules.map(\.rawValue).sorted()
    }
}
