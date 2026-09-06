@testable import Core
import SwiftParser
@testable import SwiftProjectLintRules
import SwiftSyntax
import Testing

@Suite
struct ParallelListDriftVisitorTests {

    private func analyze(files: [String: String]) -> [LintIssue] {
        var cache: [String: SourceFileSyntax] = [:]
        for (name, source) in files {
            cache[name] = Parser.parse(source: source)
        }
        let pattern = ParallelListDrift().pattern
        let visitor = ParallelListDriftVisitor(fileCache: cache)
        visitor.setPattern(pattern)

        for (name, ast) in cache {
            visitor.setFilePath(name)
            visitor.setSourceLocationConverter(SourceLocationConverter(fileName: name, tree: ast))
            visitor.walk(ast)
        }
        visitor.finalizeAnalysis()
        return visitor.detectedIssues.filter { $0.ruleName == .parallelListDrift }
    }

    // MARK: - Fires

    @Test("a strict subset missing one of a substantial list flags the deficient side")
    func enumVersusArrayStrictSubset() throws {
        // High coverage (5 of 6 = 0.83): the array is missing about one entry of a real
        // enumeration — the "forgot to add the new entry" case — so the strict subset still fires.
        let issues = analyze(files: [
            "Kind.swift": "enum TemplateKind { case header, body, footer, sidebar, hero, banner }",
            "Emit.swift": #"let emitted = ["header", "body", "footer", "sidebar", "hero"]"#
        ])
        // Only `emitted` is missing something; the enum is a superset, so it stays quiet.
        #expect(issues.count == 1)
        let issue = try #require(issues.first)
        #expect(issue.filePath == "Emit.swift")
        #expect(issue.message.contains("banner"))
        #expect(issue.message.contains("emitted"))
    }

    @Test("a low-coverage strict subset is suppressed — a curated subset, not drift")
    func curatedStrictSubsetIsSuppressed() {
        // The SwiftCompilerFlagStudio false positive: a small value list that is wholly contained
        // in a larger canonical one (3 of 4 = 0.75) is a curated subset by design, not drift.
        let issues = analyze(files: [
            "A.swift": #"let supported = ["YES", "YES_ERROR", "NO"]"#,
            "B.swift": #"let canonical = ["DEFAULT", "YES", "YES_ERROR", "NO"]"#
        ])
        #expect(issues.isEmpty)
    }

    @Test("each side missing a distinct entry produces one issue per side")
    func mutualDriftFlagsBoth() {
        let issues = analyze(files: [
            "A.swift": "enum Pack { case alpha, bravo, charlie, delta, echo }",
            "B.swift": #"let names = ["alpha", "bravo", "charlie", "delta", "foxtrot"]"#
        ])
        #expect(issues.count == 2)
        #expect(Set(issues.map(\.filePath)) == ["A.swift", "B.swift"])
    }

    @Test("normalization spans camelCase, PascalCase and kebab-case spellings")
    func namesNormalizeAcrossSpellingConventions() throws {
        // 5 of 6 = 0.83, so this fires as a substantial strict subset; the point under test is
        // that kebab-case entries normalize to the enum's camelCase cases.
        let issues = analyze(files: [
            "Cat.swift": """
            enum Category { case stateManagement, uiPatterns, codeQuality, memoryManagement, security, performance }
            """,
            "Doc.swift": #"""
            let documented = ["state-management", "ui-patterns", "code-quality", "memory-management", "security"]
            """#
        ])
        #expect(issues.count == 1)
        let issue = try #require(issues.first)
        #expect(issue.filePath == "Doc.swift")
        // The missing entry is reported in the counterpart's original spelling.
        #expect(issue.message.contains("performance"))
    }

    @Test("a registration-call run is read as a list and compared against an enum")
    func registrationRunVersusEnum() throws {
        // The motivating shape: BuiltInRules.registerAll registers category factories in a
        // trailing closure, while PatternCategory declares the categories as enum cases.
        let issues = analyze(files: [
            "PatternCategory.swift": """
            enum PatternCategory {
                case stateManagement
                case performance
                case security
                case accessibility
                case idempotency
            }
            """,
            "BuiltInRules.swift": """
            enum BuiltInRules {
                static func registerAll() {
                    SourcePatternRegistry.registerFactory { registry, visitorRegistry in
                        StateManagement(registry: registry, visitorRegistry: visitorRegistry)
                    }
                    SourcePatternRegistry.registerFactory { registry, visitorRegistry in
                        Performance(registry: registry, visitorRegistry: visitorRegistry)
                    }
                    SourcePatternRegistry.registerFactory { registry, visitorRegistry in
                        Security(registry: registry, visitorRegistry: visitorRegistry)
                    }
                    SourcePatternRegistry.registerFactory { registry, visitorRegistry in
                        Accessibility(registry: registry, visitorRegistry: visitorRegistry)
                    }
                }
            }
            """
        ])
        #expect(issues.count == 1)
        let issue = try #require(issues.first)
        #expect(issue.filePath == "BuiltInRules.swift")
        #expect(issue.message.contains("idempotency"))
        #expect(issue.message.contains("registration run"))
    }

    @Test("a run of register calls taking a plain string argument is read as a list")
    func registrationRunWithStringArguments() {
        let issues = analyze(files: [
            "Enum.swift": "enum Step { case fetch, parse, validate, persist, notify }",
            "Wire.swift": """
            func wire() {
                pipeline.register("fetch")
                pipeline.register("parse")
                pipeline.register("validate")
                pipeline.register("persist")
            }
            """
        ])
        #expect(issues.count == 1)
    }

    @Test("a list drifting against several counterparts reports only its closest one")
    func onlyTheClosestCounterpartIsReported() throws {
        let issues = analyze(files: [
            // `short` is missing entries relative to both peers, but `near` is the closer
            // match (shares 5 of 6) and is the only counterpart that should be named.
            "Short.swift": #"let short = ["alpha", "bravo", "charlie", "delta", "echo"]"#,
            "Near.swift": #"let near = ["alpha", "bravo", "charlie", "delta", "echo", "foxtrot"]"#,
            "Far.swift": #"""
            let far = ["alpha", "bravo", "charlie", "delta", "golf", "hotel", "india"]
            """#
        ])
        let onShort = issues.filter { $0.filePath == "Short.swift" }
        #expect(onShort.count == 1)
        let issue = try #require(onShort.first)
        #expect(issue.message.contains("near"))
        #expect(issue.message.contains("far") == false)
    }

    // MARK: - Does not fire

    @Test("lists that agree exactly are Parallel Enum Shape's finding, not drift")
    func exactAgreementDoesNotFire() {
        let issues = analyze(files: [
            "A.swift": "enum Pack { case alpha, bravo, charlie, delta }",
            "B.swift": #"let names = ["alpha", "bravo", "charlie", "delta"]"#
        ])
        #expect(issues.isEmpty)
    }

    @Test("lists below the four-entry floor are ignored")
    func shortListsAreIgnored() {
        let issues = analyze(files: [
            "A.swift": "enum Pack { case alpha, bravo, charlie }",
            "B.swift": #"let names = ["alpha", "bravo"]"#
        ])
        #expect(issues.isEmpty)
    }

    @Test("incidental overlap below the similarity floor does not fire")
    func lowSimilarityDoesNotFire() {
        // Shares 3 of 11 union entries (Jaccard 0.27) — two unrelated lists that happen
        // to mention the same few words.
        let issues = analyze(files: [
            "A.swift": "enum Pack { case alpha, bravo, charlie, delta, echo, foxtrot, golf }",
            "B.swift": #"let names = ["alpha", "bravo", "charlie", "xray", "yankee", "zulu", "whiskey"]"#
        ])
        #expect(issues.isEmpty)
    }

    @Test("test and fixture files are excluded — a deliberate subset is not drift")
    func testFilesAreExcluded() {
        let issues = analyze(files: [
            "Kind.swift": "enum TemplateKind { case header, body, footer, sidebar }",
            "Tests/KindTests.swift": #"let covered = ["header", "body", "footer"]"#
        ])
        #expect(issues.isEmpty)
    }

    @Test("a mixed-kind array is data, not an enumeration of names")
    func mixedArrayIsNotAList() {
        let issues = analyze(files: [
            "A.swift": "enum Pack { case alpha, bravo, charlie, delta, echo }",
            "B.swift": #"let mixed = ["alpha", .bravo, "charlie", 42, "delta"]"#
        ])
        #expect(issues.isEmpty)
    }

    @Test("interleaved callees do not form a single registration run")
    func interleavedCalleesDoNotFormARun() {
        let issues = analyze(files: [
            "A.swift": "enum Step { case fetch, parse, validate, persist, notify }",
            "B.swift": """
            func wire() {
                pipeline.register("fetch")
                other.add("parse")
                pipeline.register("validate")
                other.add("persist")
            }
            """
        ])
        #expect(issues.isEmpty)
    }
}

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
            """
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
            """
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
            """
        ]).isEmpty)
    }
}
