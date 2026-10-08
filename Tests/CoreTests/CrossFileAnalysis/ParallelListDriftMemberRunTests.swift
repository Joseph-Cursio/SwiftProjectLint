@testable import Core
import SwiftParser
@testable import SwiftProjectLintRules
import SwiftSyntax
import Testing

/// The fourth carrier: one operation applied to a run of one value's members. The fixtures are
/// SwiftLintRuleStudio's, before the fix: an import validation that forgot `analyzerRules`, beside
/// two collectors that each enumerate all five of a config's rule fields.
@Suite
struct ParallelListDriftMemberRunTests {

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

    /// `MigrationAssistant.collectAllRuleIds`.
    private static let compactCollector = """
        struct Assistant {
            func collectAllRuleIds(from config: Config) -> Set<String> {
                var ids = Set(config.rules.keys)
                if let disabled = config.disabledRules { ids.formUnion(disabled) }
                if let optIn = config.optInRules { ids.formUnion(optIn) }
                if let analyzer = config.analyzerRules { ids.formUnion(analyzer) }
                if let only = config.onlyRules { ids.formUnion(only) }
                return ids
            }
        }
        """

    /// `VersionCompatibilityChecker.collectAllRuleIds` — the same enumeration, laid out differently.
    private static let spreadCollector = """
        struct Checker {
            func collectAllRuleIds(from config: Config) -> Set<String> {
                var ids = Set(config.rules.keys)
                if let disabled = config.disabledRules {
                    ids.formUnion(disabled)
                }
                if let optIn = config.optInRules {
                    ids.formUnion(optIn)
                }
                if let analyzer = config.analyzerRules {
                    ids.formUnion(analyzer)
                }
                if let only = config.onlyRules {
                    ids.formUnion(only)
                }
                return ids
            }
        }
        """

    /// `ConfigImportService.fetchAndPreview`'s validation.
    private static let validation = """
        struct Importer {
            func preview(_ parsedConfig: Config, errors validationErrors: [String]) -> [String] {
                var errors = validationErrors
                if validationErrors.isEmpty
                    && parsedConfig.rules.isEmpty
                    && parsedConfig.disabledRules == nil
                    && parsedConfig.optInRules == nil
                    && parsedConfig.onlyRules == nil {
                    errors.append("Configuration appears empty")
                }
                return errors
            }
        }
        """

    @Test("a chain one member short of a family two other places agree on is reported, naming it")
    func chainMissingAMember() throws {
        let issues = analyze(files: [
            "Assistant.swift": Self.compactCollector,
            "Checker.swift": Self.spreadCollector,
            "Importer.swift": Self.validation
        ])
        #expect(issues.count == 1)
        let issue = try #require(issues.first)
        #expect(issue.filePath == "Importer.swift")
        #expect(issue.message.contains("`parsedConfig in preview` (member run, 4 entries)"), "got: \(issue.message)")
        #expect(issue.message.contains("missing 1: analyzerRules"))
        #expect(issue.message.contains("config in collectAllRuleIds"))
        #expect(issue.suggestion?.contains("one computed property") == true)
    }

    @Test("one superset alone is not enough: the family must be corroborated")
    func uncorroboratedSupersetIsSilent() {
        let issues = analyze(files: ["Assistant.swift": Self.compactCollector, "Importer.swift": Self.validation])
        #expect(issues.isEmpty)
    }

    @Test("an array of member reads is a run")
    func arrayOfMemberReads() throws {
        let issues = analyze(files: [
            "Assistant.swift": Self.compactCollector,
            "Checker.swift": Self.spreadCollector,
            "Check.swift": """
                func lists(_ after: Config) -> [[String]?] {
                    [after.rules, after.disabledRules, after.optInRules, after.analyzerRules]
                }
                """
        ])
        let issue = try #require(issues.first)
        #expect(issue.message.contains("`after in lists`"))
        #expect(issue.message.contains("missing 1: onlyRules"))
    }

    /// The first precision gate: `copy.a = source.a` is one list, not `copy` against `source`.
    @Test("two values read in one construct are not compared with each other")
    func oneConstructIsOneList() {
        let source = """
            func copy(_ source: Config, into copy: inout Config) {
                copy.rules = source.rules
                copy.disabledRules = source.disabledRules
                copy.optInRules = source.optInRules
                copy.analyzerRules = source.analyzerRules
                copy.onlyRules = merge(copy.onlyRules, source.onlyRules)
            }
            """
        let issues = analyze(files: ["Copy.swift": source])
        #expect(issues.isEmpty)
    }

    /// The second: a run that only assigns configures a value; it enumerates nothing.
    @Test("a run of assignments is not a run of reads")
    func assignmentsAreNotReads() {
        let setup = { (name: String, extra: String) in
            """
            func \(name)(_ label: Label) {
                label.isBezeled = false
                label.isEditable = false
                label.drawsBackground = false
                \(extra)
            }
            """
        }
        let issues = analyze(files: [
            "A.swift": setup("first", "label.isSelectable = false"),
            "B.swift": setup("second", "label.isSelectable = false"),
            "C.swift": setup("third", "")
        ])
        #expect(issues.isEmpty)
    }

    /// The fourth: what a run is missing must be what its counterpart enumerated by one operation.
    @Test("a member read beside the enumeration is a different condition, not a missing entry")
    func onlyTheCoreCanBeMissing() throws {
        let gate = { (name: String, conditions: [String]) in
            "func \(name)(_ summary: Summary) -> Bool { " + conditions.joined(separator: " && ") + " }"
        }
        let flags = ["!summary.isStatic", "!summary.isAsync", "!summary.isThrows", "!summary.isMutating"]
        let issues = analyze(files: [
            "A.swift": gate("isMeasure", ["summary.parameters.count == 1"] + flags),
            "B.swift": gate("isPredicate", ["summary.parameters.count == 1"] + flags),
            // Missing `parameters`, read beside the flags: silent.
            "C.swift": gate("isInvolution", flags),
            // Missing `isMutating`, one of the flags: reported.
            "D.swift": gate("isComparator", ["summary.parameters.count == 1"] + flags.dropLast())
        ])
        let issue = try #require(issues.first)
        #expect(issues.count == 1)
        #expect(issue.filePath == "D.swift")
        #expect(issue.message.contains("missing 1: isMutating"))
    }

    /// The third: gates that each test a different selection of one value's flags are not drift.
    @Test("runs that each read something the others do not are different selections")
    func mutualDivergenceIsSilent() {
        let gate = { (name: String, flags: [String]) in
            "func \(name)(_ summary: Summary) -> Bool { "
                + flags.map { "!summary.\($0)" }.joined(separator: " && ") + " }"
        }
        let issues = analyze(files: [
            "A.swift": gate("isMeasure", ["isStatic", "isAsync", "isThrows", "isMutating"]),
            "B.swift": gate("isPredicate", ["isStatic", "isAsync", "isThrows", "isMutating"]),
            "C.swift": gate("isComparator", ["isStatic", "isAsync", "isThrows", "isOptional"])
        ])
        #expect(issues.isEmpty)
    }
}
