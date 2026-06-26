@testable import Core
import PropertyBased
import SwiftParser
@testable import SwiftProjectLintRules
import SwiftSyntax
import Testing

/// Property-based law: **narrowing the enabled rule set is pure filtering.**
///
/// Running a *subset* `S` of the rules over a source must produce exactly the
/// issues that running *all* rules produces, restricted to `S`:
///
///     detect(source, rules: S)  ≡  detect(source, allRules).filter { S contains $0.ruleName }
///
/// This is the strong form of the existing `RuleIdentifierFilteringTests`,
/// which only checks `subset.count <= all.count`. Equality is what matters: if
/// selecting a subset ever *changes which issues a rule emits* (rather than
/// merely omitting other rules' issues), there is hidden coupling between rules
/// — shared visitor state, registry-ordering sensitivity, or a cross-rule cache.
/// That class of bug is invisible to fixed-selection example tests and is
/// exactly what this law catches.
///
/// `LintIssue` carries a random `UUID`, so issues are compared on a normalized
/// projection (rule, severity, message, suggestion, locations) as a multiset.
@Suite
@MainActor
struct RuleSelectionFilteringPropertyTests {

    /// A single-file source crafted to trip several independent rules so the
    /// filtering law has real content to permute.
    private static let source = """
    import SwiftUI

    struct DashboardView: View {
        @State private var isLoading = false
        @State private var unusedFlag = false
        @State private var isLoadingCopy = false

        var body: some View {
            VStack {
                Text("Hello")
                Button("Tap me") {
                    print("tapped")
                }
                Image("icon")
            }
        }
    }

    final class DataManager {
        static let shared = DataManager()
        private init() {}
    }
    """

    private static let filePath = "/RuleSelectionFiltering.swift"

    /// Normalizes issues to a comparable, order-independent multiset key,
    /// excluding the random `UUID` and folding multi-location issues into a
    /// stable string.
    private static func normalize(_ issues: [LintIssue]) -> [String] {
        issues.map { issue in
            let locations = issue.locations
                .map { "\($0.filePath):\($0.lineNumber)" }
                .sorted()
                .joined(separator: ",")
            return [
                issue.ruleName.rawValue,
                "\(issue.severity)",
                issue.message,
                issue.suggestion ?? "",
                locations
            ].joined(separator: "§")
        }
        .sorted()
    }

    @Test
    func ruleSelection_isPureFiltering() async {
        let detector = TestRegistryManager.getSharedDetector()
        let ast = Parser.parse(source: Self.source)

        let allIssues = detector.detectPatterns(
            in: Self.source,
            filePath: Self.filePath,
            parsedAST: ast
        )

        // The fired rules — the only ones whose inclusion/exclusion changes the
        // result. Sorted for a deterministic mask alignment.
        let firedRules = Array(Set(allIssues.map(\.ruleName)))
            .sorted { $0.rawValue < $1.rawValue }

        // Non-vacuity: the source must trip multiple rules, or the law below is
        // empty. The message surfaces what actually fired if this regresses.
        #expect(
            firedRules.count >= 2,
            "Source should trip ≥2 rules; fired: \(firedRules.map(\.rawValue))"
        )

        let boolGen = Gen<Bool>.oneOf(Gen.always(true), Gen.always(false))
        let maskGen = boolGen.array(of: firedRules.count)

        await propertyCheck(input: maskGen) { mask in
            let selected = zip(firedRules, mask).filter(\.1).map(\.0)
            let selectedSet = Set(selected)

            let subsetIssues = detector.detectPatterns(
                in: Self.source,
                filePath: Self.filePath,
                ruleIdentifiers: selected,
                parsedAST: ast
            )
            let expected = allIssues.filter { selectedSet.contains($0.ruleName) }

            #expect(Self.normalize(subsetIssues) == Self.normalize(expected))
        }
    }
}
