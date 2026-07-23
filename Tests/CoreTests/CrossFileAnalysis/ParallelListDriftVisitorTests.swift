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

    @Test("enum and array literal that drift by one entry flag the deficient side only")
    func enumVersusArrayStrictSubset() throws {
        let issues = analyze(files: [
            "Kind.swift": "enum TemplateKind { case header, body, footer, sidebar }",
            "Emit.swift": #"let emitted = ["header", "body", "footer"]"#
        ])
        // Only `emitted` is missing something; the enum is a superset, so it stays quiet.
        #expect(issues.count == 1)
        let issue = try #require(issues.first)
        #expect(issue.filePath == "Emit.swift")
        #expect(issue.message.contains("sidebar"))
        #expect(issue.message.contains("emitted"))
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
        let issues = analyze(files: [
            "Cat.swift": "enum Category { case stateManagement, uiPatterns, codeQuality, memoryManagement }",
            "Doc.swift": #"let documented = ["state-management", "ui-patterns", "code-quality"]"#
        ])
        #expect(issues.count == 1)
        let issue = try #require(issues.first)
        #expect(issue.filePath == "Doc.swift")
        // The missing entry is reported in the counterpart's original spelling.
        #expect(issue.message.contains("memoryManagement"))
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
