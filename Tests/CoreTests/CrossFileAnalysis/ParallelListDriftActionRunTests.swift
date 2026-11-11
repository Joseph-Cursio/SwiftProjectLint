import SwiftParser
import SwiftProjectLintModels
@testable import SwiftProjectLintRules
import SwiftProjectLintVisitors
import SwiftSyntax
import Testing

/// A menu built as sibling calls is an enumeration transcribed by hand.
///
/// This carrier exists because of a real defect the rule could not see. A title menu was eleven
/// `Button`s against a twelve-case enum and silently omitted one destination — reachable from the
/// sidebar and from nowhere else. Written as `[.rules, .reports, …]` the rule reported it and
/// named the missing case; written as eleven calls it saw nothing.
///
/// Two things had to change. `Button` is not a `RegistrationVerb`, so the run was never collected;
/// and the first name-like argument is the *label* (`"Enabled Rule Violations"`), which normalizes
/// nowhere near the case name it belongs to. The entry has to come from the action.
@Suite("A run of sibling calls carries the roster its actions name")
struct ParallelListDriftActionRunTests {

    private func analyze(files: [String: String]) -> [LintIssue] {
        var cache: [String: SourceFileSyntax] = [:]
        for (name, source) in files {
            cache[name] = Parser.parse(source: source)
        }
        let visitor = ParallelListDriftVisitor(fileCache: cache)
        visitor.setPattern(ParallelListDrift().pattern)
        for (name, ast) in cache {
            visitor.setFilePath(name)
            visitor.setSourceLocationConverter(SourceLocationConverter(fileName: name, tree: ast))
            visitor.walk(ast)
        }
        visitor.finalizeAnalysis()
        return visitor.detectedIssues.filter { $0.ruleName == .parallelListDrift }
    }

    private static let sections = """
    enum AppSection {
        case rules, violations, exportReport, dashboard, ruleAudit
        case versionHistory, compareConfigs, versionCheck, importConfig
        case branchDiff, migration, configMap
    }
    """

    @Test("a menu missing one case is reported, and the missing case is named")
    func menuMissingOneCaseIsReported() {
        let issues = analyze(files: [
            "Section.swift": Self.sections,
            "Menu.swift": """
            struct TitleMenu: View {
                var body: some View {
                    Button("Rules") { selection = .rules }
                    Button("Violations") { selection = .violations }
                    Button("Export") { selection = .exportReport }
                    Button("Dashboard") { selection = .dashboard }
                    Button("Audit") { selection = .ruleAudit }
                    Button("History") { selection = .versionHistory }
                    Button("Compare") { selection = .compareConfigs }
                    Button("Check") { selection = .versionCheck }
                    Button("Import") { selection = .importConfig }
                    Button("Diff") { selection = .branchDiff }
                    Button("Migration") { selection = .migration }
                }
            }
            """,
        ])
        #expect(issues.count == 1)
        #expect(issues.first?.message.contains("configMap") == true)
    }

    /// The precision lever, and the reason arguments are not searched.
    ///
    /// Reading arguments too collected `.red`, `.green` and `.primary` out of lists of summary
    /// tiles, so two unrelated views drawing four tiles apiece paired on three shared colour names
    /// and reported drift against each other. Both were false positives. A roster entry is what
    /// the item *does*, not how it is *styled*.
    @Test("styling arguments are not roster entries")
    func stylingArgumentsAreNotEntries() {
        #expect(analyze(files: [
            "Left.swift": """
            struct Left: View {
                var body: some View {
                    summaryItem(count: a, label: "Only in Left", color: .red)
                    summaryItem(count: b, label: "Only in Right", color: .green)
                    summaryItem(count: c, label: "Changed", color: .orange)
                    summaryItem(count: d, label: "Same", color: .primary)
                }
            }
            """,
            "Right.swift": """
            struct Right: View {
                var body: some View {
                    SummaryCard(title: "TOTAL", color: .primary)
                    SummaryCard(title: "ERRORS", color: .red)
                    SummaryCard(title: "WARNINGS", color: .orange)
                    SummaryCard(title: "PASSED", color: .green)
                }
            }
            """,
        ]).isEmpty)
    }

    /// An action naming two things cannot contribute one entry without choosing between them.
    @Test("an action naming two members contributes nothing")
    func ambiguousActionContributesNothing() {
        #expect(analyze(files: [
            "Section.swift": Self.sections,
            "Menu.swift": """
            struct TitleMenu: View {
                var body: some View {
                    Button("A") { selection = .rules; mode = .compact }
                    Button("B") { selection = .violations; mode = .compact }
                    Button("C") { selection = .exportReport; mode = .compact }
                    Button("D") { selection = .dashboard; mode = .compact }
                }
            }
            """,
        ]).isEmpty)
    }

    // MARK: - A tagged union over types is not a vocabulary (#190)

    /// **Two lists over one closed vocabulary answer different questions**, and nothing about name
    /// overlap distinguishes that from drift — the difference lives in what the list *is*.
    ///
    /// When an enum's case names are their own payloads' type names, the roster is not a
    /// vocabulary anybody chose: it is Swift's scalar types, spelled once per case because the
    /// enum is a value tree over them. Comparing it against a list of type names finds an overlap
    /// the language guarantees. That is `MinimalCodableValue` against `RawType`, which agreed on
    /// fourteen names and had nothing to do with each other.
    @Test("an enum whose cases name their payload types is not compared")
    func taggedUnionOverTypesIsNotAList() {
        let issues = analyze(files: [
            "Tree.swift": """
            enum JSONValue {
                case null
                case bool(Bool)
                case int(Int)
                case double(Double)
                case string(String)
            }
            """,
            "Table.swift": """
            struct Scalars {
                static let supported = ["bool", "int", "double", "string", "float", "int8"]
            }
            """,
        ])
        #expect(issues.isEmpty)
    }

    /// **What the narrowing must not lose**, and the reason it is not "associated values
    /// disqualify". The rule compares a roster of names, and `failure` is not `Error` — that case
    /// still contributes the name a parallel list is expected to carry.
    @Test("an enum with associated values that are not its case names is still compared")
    func associatedValuesAloneDoNotExempt() {
        let issues = analyze(files: [
            "Outcome.swift": """
            enum Outcome {
                case success(Payload)
                case failure(Error)
                case cancelled(Reason)
                case timedOut(Duration)
                case retried(Attempt)
                case skipped(Cause)
                case deferred(Until)
                case rejected(Rule)
            }
            """,
            "Labels.swift": """
            struct Labels {
                static let all = [
                    "success", "failure", "cancelled", "timedOut",
                    "retried", "skipped", "deferred"
                ]
            }
            """,
        ])
        #expect(!issues.isEmpty)
    }

    /// A single echoing case is a coincidence rather than a shape, so two are required before the
    /// enum is read as a value tree.
    @Test("one case naming its payload type does not exempt an enum")
    func oneEchoingCaseIsNotEnough() {
        let issues = analyze(files: [
            "Mixed.swift": """
            enum Mixed {
                case int(Int)
                case failure(Error)
                case cancelled(Reason)
                case retried(Attempt)
                case skipped(Cause)
                case deferred(Until)
                case rejected(Rule)
                case timedOut(Duration)
            }
            """,
            "Labels.swift": """
            struct Labels {
                static let all = [
                    "int", "failure", "cancelled", "retried",
                    "skipped", "deferred", "rejected"
                ]
            }
            """,
        ])
        #expect(!issues.isEmpty)
    }
}
