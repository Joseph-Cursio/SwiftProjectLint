@testable import Core
import PropertyBased
import SwiftParser
@testable import SwiftProjectLintRules
import SwiftSyntax
import Testing

/// Property-based law: **inline suppression only removes what it targets.**
///
/// Blanket-disabling a set `D` of rules over a source must yield exactly the
/// detected issues whose rule is *not* in `D`:
///
///     filter(detect(src+disables(D)), src+disables(D))  ≡  detect(...).filter { $0.ruleName ∉ D }
///
/// This is a single law capturing two guarantees at once:
/// - **Soundness** — suppressing `D` never removes an issue belonging to a rule
///   outside `D`. A suppression that silently swallows an *unrelated* diagnostic
///   is a near-undetectable safety bug; this is what catches it.
/// - **Completeness** — every issue of a disabled rule is in fact removed.
///
/// Detection and filtering both run over the *same* directive-bearing source, so
/// issue line numbers and directive ranges stay aligned — no line-shift confound
/// from comparing against a directive-free variant. `LintIssue`'s random `UUID`
/// is excluded via the normalized projection.
@Suite
@MainActor
struct SuppressionSoundnessPropertyTests {

    /// A single-file source that trips several independent rules, so disabling
    /// subsets of them is meaningful.
    private static let baseSource = """
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

    private static let filePath = "/SuppressionSoundness.swift"

    /// Order-independent multiset key excluding the random `UUID`.
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
    func disablingRules_removesOnlyThoseRulesIssues() async {
        let detector = TestRegistryManager.getSharedDetector()

        let baseIssues = detector.detectPatterns(
            in: Self.baseSource,
            filePath: Self.filePath,
            parsedAST: Parser.parse(source: Self.baseSource)
        )
        let firedRules = Array(Set(baseIssues.map(\.ruleName)))
            .sorted { $0.rawValue < $1.rawValue }

        #expect(
            firedRules.count >= 2,
            "Source should trip ≥2 rules; fired: \(firedRules.map(\.rawValue))"
        )

        let boolGen = Gen<Bool>.oneOf(Gen.always(true), Gen.always(false))
        let maskGen = boolGen.array(of: firedRules.count)

        await propertyCheck(input: maskGen) { mask in
            let disabled = zip(firedRules, mask).filter(\.1).map(\.0)
            let disabledSet = Set(disabled)

            // Prepend a whole-file disable directive for each selected rule.
            // Detect and filter on this same content so lines stay aligned.
            let directiveLines = disabled.map { "// swiftprojectlint:disable \($0.suppressionKey)" }
            let directiveSource = (directiveLines + [Self.baseSource]).joined(separator: "\n")
            let ast = Parser.parse(source: directiveSource)

            let raw = detector.detectPatterns(
                in: directiveSource,
                filePath: Self.filePath,
                parsedAST: ast
            )
            let filtered = InlineSuppressionFilter.filter(raw, fileContent: directiveSource)
            let expected = raw.filter { !disabledSet.contains($0.ruleName) }

            #expect(Self.normalize(filtered) == Self.normalize(expected))
        }
    }
}
