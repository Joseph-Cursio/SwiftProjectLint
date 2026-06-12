@testable import Core
import SwiftParser
@testable import SwiftProjectLintRules
import SwiftSyntax
import Testing

@Suite
struct UnusedProtocolAbstractionVisitorTests {

    private func analyze(files: [String: String]) -> [LintIssue] {
        var cache: [String: SourceFileSyntax] = [:]
        for (name, source) in files {
            cache[name] = Parser.parse(source: source)
        }
        let pattern = UnusedProtocolAbstraction().pattern
        let visitor = UnusedProtocolAbstractionVisitor(fileCache: cache)
        visitor.setPattern(pattern)

        for (name, ast) in cache {
            visitor.setFilePath(name)
            visitor.setSourceLocationConverter(SourceLocationConverter(fileName: name, tree: ast))
            visitor.walk(ast)
        }
        visitor.finalizeAnalysis()
        return visitor.detectedIssues.filter { $0.ruleName == .unusedProtocolAbstraction }
    }

    /// A protocol with conformers but no use as a type is flagged.
    @Test
    func conformedButNeverUsedFlags() throws {
        let issues = analyze(files: [
            "Models.swift": """
            protocol Identity { var id: String { get } }
            struct A: Identity { let id: String }
            struct B: Identity { let id: String }
            """
        ])

        #expect(issues.count == 1)
        let issue = try #require(issues.first)
        #expect(issue.message.contains("Identity"))
    }

    /// Conformers declared with an isolated conformance still count toward the conformer total.
    @Test
    func isolatedConformanceConformersAreCounted() {
        let issues = analyze(files: [
            "Models.swift": """
            protocol Identity { var id: String { get } }
            struct A: @MainActor Identity { let id: String }
            """
        ])

        #expect(issues.count == 1)
    }

    /// Used as a generic constraint → not flagged.
    @Test
    func usedAsConstraintIsClean() {
        let issues = analyze(files: [
            "Models.swift": """
            protocol Identity { var id: String { get } }
            struct A: Identity { let id: String }
            func describe<T: Identity>(_ value: T) -> String { value.id }
            """
        ])

        #expect(issues.isEmpty)
    }

    /// Used as an existential parameter → not flagged.
    @Test
    func usedAsExistentialIsClean() {
        let issues = analyze(files: [
            "Models.swift": """
            protocol Identity { var id: String { get } }
            struct A: Identity { let id: String }
            func log(_ value: any Identity) { _ = value.id }
            """
        ])

        #expect(issues.isEmpty)
    }

    /// No conformers → not flagged (the rule targets unused *abstractions*, not unused protocols).
    @Test
    func noConformersIsClean() {
        let issues = analyze(files: [
            "Models.swift": """
            protocol Identity { var id: String { get } }
            """
        ])

        #expect(issues.isEmpty)
    }

    /// Refinement by another protocol counts as a use → not flagged.
    @Test
    func refinedByAnotherProtocolIsClean() {
        let issues = analyze(files: [
            "Models.swift": """
            protocol Base { var id: String { get } }
            protocol Extended: Base { var name: String { get } }
            struct A: Base { let id: String }
            func use(_ value: any Extended) { _ = value.id }
            """
        ])

        // `Base` is used via `Extended`'s refinement; `Extended` is used as an existential.
        #expect(issues.isEmpty)
    }

    /// A file-scoped (`fileprivate`) dead protocol is flagged even when an unrelated
    /// same-named type is used as a type in another file — that homonym cannot refer
    /// to the file-scoped protocol, so it no longer masks it.
    @Test
    func fileScopedProtocolNotMaskedByHomonymInAnotherFile() throws {
        let issues = analyze(files: [
            "A.swift": """
            fileprivate protocol Identity { var id: String { get } }
            struct A: Identity { let id: String }
            """,
            "B.swift": """
            struct Identity { let id: String }
            func use(_ value: Identity) { _ = value.id }
            """
        ])

        #expect(issues.count == 1)
        let issue = try #require(issues.first)
        #expect(issue.message.contains("Identity"))
    }

    /// Internal protocols remain name-global: AST-only analysis can't resolve modules,
    /// and within a single module a same-named reference plausibly *is* the protocol,
    /// so a use elsewhere still counts. Documents the deliberate scope boundary.
    @Test
    func internalProtocolStaysGloballyScoped() {
        let issues = analyze(files: [
            "A.swift": """
            protocol Identity { var id: String { get } }
            struct A: Identity { let id: String }
            """,
            "B.swift": """
            func use(_ value: Identity) { _ = value }
            """
        ])

        #expect(issues.isEmpty)
    }
}
