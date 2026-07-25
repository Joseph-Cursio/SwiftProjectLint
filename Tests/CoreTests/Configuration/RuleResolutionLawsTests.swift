@testable import Core
import PropertyBased
import Testing

/// Property-based set algebra for `LintConfiguration.resolveRules(…)` — the
/// function that decides **which of the 197 rules actually run**.
///
/// Everything downstream is filtered by this answer, so a mistake here is not a
/// wrong diagnostic, it is a *missing* one: rules that quietly stop running
/// while the tool still reports success. The existing
/// `RuleSelectionFilteringPropertyTests` checks that the detector faithfully
/// honours a rule set it is handed; nothing checked how that set is computed
/// until now.
///
/// ## The law worth the whole file
///
/// `resolveRules` computes the default rule set **twice**, in two different
/// spellings, forty lines apart:
///
/// ```swift
/// var rules = Set(RuleIdentifier.allCases)      // …then remove/subtract, imperatively
/// rules.remove(.unknown); rules.remove(.fileParsingError)
/// … rules.subtract(Self.optInRules)
///
/// let allRules = Set(RuleIdentifier.allCases)   // …and again, functionally
///     .subtracting([.unknown, .fileParsingError])
///     .subtracting(Self.optInRules)
/// ```
///
/// The second is compared against the first to decide whether to return `nil`
/// ("no restriction"). The two must agree, and nothing makes them agree — no
/// shared constant, no type. Adding a rule to `optInRules` in one place and not
/// the other, or adding a third sentinel, silently flips a default run from "no
/// filtering" to "filter to this explicit list", which changes behaviour for
/// every caller that treats `nil` specially. `defaultConfigurationIsUnrestricted`
/// is the law that ties them together.
@Suite
struct RuleResolutionLawsTests {

    // MARK: - Reference definitions

    private static let sentinels: Set<RuleIdentifier> = [.unknown, .fileParsingError]

    /// The set a default run is expected to produce, stated once, independently
    /// of either spelling inside `resolveRules`.
    private static let expectedDefaultSet: Set<RuleIdentifier> =
        Set(RuleIdentifier.allCases)
            .subtracting(sentinels)
            .subtracting(LintConfiguration.optInRules)

    // MARK: - Generators

    // `element(of:)` is nil-returning only for an empty collection; these pools
    // are non-empty constants, so coalescing keeps the generator total.
    private static let ruleGen = Gen<RuleIdentifier?>.element(of: RuleIdentifier.allCases)
        .map { $0 ?? .forceTry }

    /// Small subsets: large ones would make `enabled_only` swallow the whole
    /// catalog and stop distinguishing the laws.
    private static let ruleSetGen = ruleGen.array(of: 0...6).map { Set($0) }

    private static let categoryGen = Gen<PatternCategory?>.element(of: PatternCategory.allCases)
        .map { $0 ?? .codeQuality }
    private static let categoriesGen = categoryGen.array(of: 1...3)

    // MARK: - Laws

    /// **L6.6 — `nil` means exactly "nothing was restricted".**
    ///
    /// The duplicated-expression law described above. A default configuration
    /// with no CLI narrowing must return `nil`; any configuration that *does*
    /// narrow must not.
    @Test
    func defaultConfigurationIsUnrestricted() {
        #expect(LintConfiguration.default.resolveRules() == nil)

        // And the two spellings agree on *what* the default set is: asking for
        // every category explicitly forces the non-nil branch, and that answer
        // must equal the independently-stated reference set.
        let viaCategories = LintConfiguration.default.resolveRules(
            cliCategories: PatternCategory.allCases
        )
        #expect(Set(viaCategories ?? []) == Self.expectedDefaultSet)
    }

    /// Any non-empty `disabledRules` genuinely restricts, so the result must be
    /// a concrete list rather than `nil`. A `nil` here would mean "run
    /// everything" — the disabled rules would come back to life.
    @Test
    func disablingAnythingProducesARestrictedList() async {
        await propertyCheck(input: Self.ruleSetGen) { disabled in
            // Only rules that are actually part of a default run can restrict it.
            let effective = disabled.intersection(Self.expectedDefaultSet)
            let resolved = LintConfiguration(disabledRules: disabled).resolveRules()

            if effective.isEmpty {
                // Disabling only opt-in or sentinel rules changes nothing.
                #expect(resolved == nil)
            } else {
                let result = try #require(resolved)
                #expect(Set(result) == Self.expectedDefaultSet.subtracting(effective))
            }
        }
    }

    /// **L6.1 + L6.2 — disabled rules and sentinels never survive.**
    @Test
    func disabledRulesAndSentinelsAreNeverResolved() async {
        await propertyCheck(input: Self.ruleSetGen, Self.ruleSetGen) { disabled, enabledOnly in
            let config = LintConfiguration(
                disabledRules: disabled,
                enabledOnlyRules: enabledOnly.isEmpty ? nil : enabledOnly
            )
            guard let resolved = config.resolveRules() else { return }
            let result = Set(resolved)

            #expect(result.isDisjoint(with: disabled), "a disabled rule was resolved")
            #expect(result.isDisjoint(with: Self.sentinels), "a sentinel rule was resolved")
        }
    }

    /// **L6.3 — opt-in rules stay off unless `enabled_only` names them.**
    ///
    /// These rules are noisy by design and off by default. A regression that
    /// let them leak into a default run would flood every adopter's output; one
    /// that dropped them from an explicit `enabled_only` would make them
    /// unreachable.
    @Test
    func optInRulesRequireExplicitEnabling() async {
        await propertyCheck(input: Self.ruleSetGen) { disabled in
            // Not named: must be absent.
            let plain = LintConfiguration(disabledRules: disabled).resolveRules()
            #expect(Set(plain ?? Array(Self.expectedDefaultSet)).isDisjoint(with: LintConfiguration.optInRules))

            // Named via enabled_only, and not disabled: must be present.
            let wanted = LintConfiguration.optInRules.subtracting(disabled)
            let opted = LintConfiguration(
                disabledRules: disabled,
                enabledOnlyRules: LintConfiguration.optInRules
            ).resolveRules()
            #expect(Set(opted ?? []) == wanted)
        }
    }

    /// **L6.4 — explicit CLI rules take full precedence.**
    ///
    /// The early return sits above every other consideration, so an explicit
    /// `--rules` list must win over `disabled_rules`, `enabled_only`, opt-in
    /// status and categories alike. This is the law that keeps `--rules` a
    /// reliable escape hatch when a config file is fighting you.
    @Test
    func explicitCLIRulesOverrideEverything() async {
        await propertyCheck(input: Self.ruleSetGen, Self.ruleSetGen) { explicit, disabled in
            let requested = Array(explicit)
            let config = LintConfiguration(
                disabledRules: disabled,
                enabledOnlyRules: [.forceTry]
            )
            let resolved = config.resolveRules(
                cliCategories: [.security],
                cliRuleIdentifiers: requested
            )
            #expect(resolved == requested, "an explicit --rules list was modified by the configuration")
        }
    }

    /// **L6.5 — a category restriction is exactly a filter.**
    ///
    /// Restricting to categories `C` yields precisely the unrestricted answer
    /// filtered by `C` — no rule gained, none lost for an unrelated reason.
    @Test
    func categoryRestrictionIsPureFiltering() async {
        await propertyCheck(input: Self.categoriesGen, Self.ruleSetGen) { categories, disabled in
            let config = LintConfiguration(disabledRules: disabled)

            let unrestricted = Set(config.resolveRules() ?? Array(Self.expectedDefaultSet))
            let restricted = Set(config.resolveRules(cliCategories: categories) ?? [])

            #expect(restricted == unrestricted.filter { categories.contains($0.category) })
            // Every surviving rule really is in one of the requested categories.
            for rule in restricted {
                #expect(categories.contains(rule.category))
            }
        }
    }

    /// Resolution is idempotent in the sense that matters: feeding the resolved
    /// list back as an explicit CLI selection reproduces it exactly.
    @Test
    func resolvedListSurvivesBeingFedBackAsAnExplicitSelection() async {
        await propertyCheck(input: Self.ruleSetGen) { disabled in
            let config = LintConfiguration(disabledRules: disabled)
            let once = config.resolveRules() ?? Array(Self.expectedDefaultSet)
            let twice = config.resolveRules(cliRuleIdentifiers: once)
            #expect(twice == once)
        }
    }
}
