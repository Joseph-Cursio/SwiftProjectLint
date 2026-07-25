@testable import Core
import PropertyBased
import Testing

/// Round-trip laws for `InlineSuppressionParser` — **every directive this
/// codebase can name, it can also read back**.
///
/// The existing `SuppressionSoundnessPropertyTests` checks the *effect* of
/// suppression end-to-end (disabling `D` removes exactly `D`'s issues). It
/// exercises one directive spelling on a handful of rules. These laws check the
/// *parser* instead, across the whole directive grammar and all 197 rules.
///
/// ## The hazard this exists for
///
/// `parseKindAndRules` matches its keywords in list order:
///
/// ```swift
/// ("disable:next", .disableNext),
/// ("disable:this", .disableThis),
/// ("disable",      .disable),
/// ("enable",       .enable)
/// ```
///
/// That order is **load-bearing and undocumented**. `"disable"` is a prefix of
/// `"disable:next"`, so hoisting the shorter entry above the longer ones — an
/// entirely natural-looking alphabetisation — makes every `disable:next`
/// directive parse as a plain `disable` whose "rule list" is the string
/// `":next force-try"`. Those tokens then fail the `keyToRule` lookup and are
/// *silently dropped* (the parser ignores unknown tokens on purpose, so future
/// rules don't break old files). The result is a `disable` with an empty rule
/// set, which means **all rules, from here to end of file**.
///
/// So the failure mode of reordering four lines is: a one-line suppression
/// silently becomes a file-wide one. Every existing example test passes, because
/// they assert on the rules that *were* suppressed, never on the ones that
/// should not have been.
@Suite
struct InlineSuppressionParserRoundTripTests {

    /// The four directive spellings, paired with the kind each must parse to.
    private static let spellings: [(text: String, kind: SuppressionDirective.Kind)] = [
        ("disable", .disable),
        ("enable", .enable),
        ("disable:next", .disableNext),
        ("disable:this", .disableThis)
    ]

    private static func line(_ spelling: String, _ keys: [String]) -> String {
        let tail = keys.isEmpty ? "" : " " + keys.joined(separator: " ")
        return "// swiftprojectlint:\(spelling)\(tail)"
    }

    /// **L3.1 — directive round-trip, exhaustive.** For every rule and every
    /// spelling, the rendered directive parses back to exactly that kind and
    /// that one rule.
    ///
    /// 197 rules × 4 spellings = 788 cases, checked exhaustively rather than
    /// sampled: the domain is finite, and a sampled run would have to be lucky
    /// to draw the single rule whose key was mistyped.
    ///
    /// This law subsumes the keyword-ordering hazard above — under the
    /// alphabetised ordering, all 197 `disable:next` cases fail at once.
    @Test
    func everyRuleRoundTripsThroughEverySpelling() {
        for rule in RuleIdentifier.allCases {
            for spelling in Self.spellings {
                let source = Self.line(spelling.text, [rule.suppressionKey])
                let parsed = InlineSuppressionParser.parse(fileContent: source)

                #expect(
                    parsed.count == 1,
                    "'\(source)' parsed to \(parsed.count) directives, expected 1"
                )
                guard let directive = parsed.first else { continue }
                #expect(
                    directive.kind == spelling.kind,
                    "'\(source)' parsed as \(directive.kind), expected \(spelling.kind)"
                )
                #expect(
                    directive.rules == [rule],
                    "'\(source)' parsed to rules \(directive.rules), expected exactly [\(rule)]"
                )
            }
        }
    }

    /// **L3.4 — the bare form means "all rules".** A directive with no rule
    /// names parses to an empty rule set, which downstream is read as "every
    /// rule", not as "no rules".
    @Test
    func bareDirectivesParseToTheEmptyRuleSet() {
        for spelling in Self.spellings {
            let parsed = InlineSuppressionParser.parse(fileContent: Self.line(spelling.text, []))
            #expect(parsed.count == 1)
            #expect(parsed.first?.kind == spelling.kind)
            #expect(parsed.first?.rules.isEmpty == true)
        }
    }

    /// **L3.2 — line numbers are 1-based and exact.** A directive on line *n*
    /// reports `line == n`.
    ///
    /// Generated rather than enumerated: the interesting variation is the
    /// *padding* around the directive, not the directive itself. Suppression
    /// ranges are computed from these numbers, so an off-by-one shifts every
    /// suppressed region by a line — which an example test written against the
    /// same off-by-one would happily ratify.
    @Test
    func directiveLineNumbersAreExact() async {
        let paddingGen = Gen<Int>.int(in: 0...12)

        await propertyCheck(input: paddingGen, paddingGen) { before, after in
            let body = Array(repeating: "let filler = 0", count: before)
                + ["// swiftprojectlint:disable force-try"]
                + Array(repeating: "let trailing = 0", count: after)

            let parsed = InlineSuppressionParser.parse(fileContent: body.joined(separator: "\n"))

            #expect(parsed.count == 1)
            // 1-based: `before` lines precede it, so it sits on line before + 1.
            #expect(parsed.first?.line == before + 1)
        }
    }

    /// **L3.3 — unknown tokens are ignored, never fatal, and never widen the
    /// directive.**
    ///
    /// Unknown rule names are dropped by design so a new rule name in a config
    /// doesn't break an older tool. The risk in that design is *silent
    /// widening*: if a typo'd rule name reduced the set to empty, the directive
    /// would flip meaning from "suppress this one rule" to "suppress
    /// everything". This law pins the recognised subset exactly.
    @Test
    func unknownTokensAreDroppedWithoutWideningTheDirective() async {
        // `element(of:)` returns nil only for an empty collection; these pools are
        // non-empty constants, so coalescing keeps the generator total.
        let ruleGen = Gen<RuleIdentifier?>.element(of: RuleIdentifier.allCases)
            .map { $0 ?? .forceTry }
        // Genuinely unrecognisable tokens only. `"FORCE-TRY"` was in this pool
        // on the first run and the law failed on it — correctly: `parseRules`
        // lowercases before lookup, so it is a real rule name, not junk. See
        // `ruleNameMatchingIsCaseInsensitive` below, which pins that behaviour
        // rather than papering over it.
        let junkGen = Gen<String?>.element(of: ["not-a-rule", "xxx", "force_try", "zzz-unknown", "1"])
            .map { $0 ?? "xxx" }

        await propertyCheck(input: ruleGen.array(of: 0...4), junkGen.array(of: 0...4)) { rules, junk in
            let keys = rules.map(\.suppressionKey) + junk
            let parsed = InlineSuppressionParser.parse(fileContent: Self.line("disable", keys.shuffled()))

            // A directive is always produced — junk never suppresses the line itself.
            #expect(parsed.count == 1)
            guard let directive = parsed.first else { return }

            // Exactly the recognised rules survive: no junk admitted, none of the
            // real ones lost.
            #expect(directive.rules == Set(rules))
        }
    }

    /// Rule names in a directive are matched **case-insensitively**.
    ///
    /// Found by the law above rather than by reading the code: `"FORCE-TRY"` was
    /// seeded into that test's junk pool as an obviously-invalid token, and the
    /// property failed because `parseRules` lowercases each token before the
    /// `keyToRule` lookup, so it resolves to `.forceTry`.
    ///
    /// The behaviour is reasonable and worth keeping — but it was undocumented,
    /// untested, and load-bearing in one direction: because unknown tokens are
    /// silently dropped, a user who types a rule name in the wrong case gets a
    /// *working* directive today, and would get a silently-widened one if the
    /// `.lowercased()` were ever removed. Pinned here so that stays a decision.
    @Test
    func ruleNameMatchingIsCaseInsensitive() {
        for spelling in ["force-try", "FORCE-TRY", "Force-Try", "fOrCe-TrY"] {
            let parsed = InlineSuppressionParser.parse(fileContent: Self.line("disable", [spelling]))
            #expect(
                parsed.first?.rules == [.forceTry],
                "'\(spelling)' did not resolve to .forceTry"
            )
        }
    }

    /// **L3.5 — non-directive content is inert.** Lines that merely mention the
    /// tool, or use a near-miss prefix, produce nothing.
    ///
    /// The parser matches on `"// swiftprojectlint:"`, so anything that isn't
    /// that exact prefix (after trimming) must be ignored. Over-eager matching
    /// here would let prose in a doc comment start suppressing rules.
    @Test
    func nonDirectiveLinesProduceNothing() {
        let inert = [
            "let x = 0",
            "// swiftprojectlint is a linter",
            "/// swiftprojectlint:disable force-try",
            "// swiftprojectlint:banana force-try",
            "// swiftlint:disable force_try",
            "let s = \"// swiftprojectlint:disable force-try\"",
            ""
        ]
        for source in inert {
            #expect(
                InlineSuppressionParser.parse(fileContent: source).isEmpty,
                "'\(source)' should not parse as a directive"
            )
        }
    }

    /// Leading whitespace is tolerated — directives are written at the
    /// indentation of the code they guard, which is the normal case, not an
    /// edge case.
    @Test
    func indentedDirectivesStillParse() async {
        await propertyCheck(input: Gen<Int>.int(in: 0...16)) { indent in
            let source = String(repeating: " ", count: indent) + "// swiftprojectlint:disable force-try"
            let parsed = InlineSuppressionParser.parse(fileContent: source)
            #expect(parsed.count == 1)
            #expect(parsed.first?.rules == [.forceTry])
        }
    }
}
