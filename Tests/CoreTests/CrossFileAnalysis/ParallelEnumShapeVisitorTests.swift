@testable import Core
import SwiftParser
@testable import SwiftProjectLintRules
import SwiftSyntax
import Testing

@Suite
struct ParallelEnumShapeVisitorTests {

    private func analyze(files: [String: String]) -> [LintIssue] {
        var cache: [String: SourceFileSyntax] = [:]
        for (name, source) in files {
            cache[name] = Parser.parse(source: source)
        }
        let pattern = ParallelEnumShape().pattern
        let visitor = ParallelEnumShapeVisitor(fileCache: cache)
        visitor.setPattern(pattern)

        for (name, ast) in cache {
            visitor.setFilePath(name)
            visitor.setSourceLocationConverter(SourceLocationConverter(fileName: name, tree: ast))
            visitor.walk(ast)
        }
        visitor.finalizeAnalysis()
        return visitor.detectedIssues.filter { $0.ruleName == .parallelEnumShape }
    }

    // MARK: - Fires

    @Test
    func twinEnumsWithNoSharedProtocolFlagsBoth() throws {
        let issues = analyze(files: [
            "Conflict.swift": "enum ConflictSeverity { case error, info, warning }",
            "Validation.swift": "enum Severity { case error, info, warning }"
        ])
        #expect(issues.count == 2)
        let first = try #require(issues.first)
        #expect(first.message.contains("error, info, warning"))
        // Each issue names the other enum as a peer.
        #expect(issues.allSatisfy { $0.message.contains("ConflictSeverity") || $0.message.contains("Severity") })
    }

    @Test
    func ubiquitousConformancesDoNotCountAsSharedProtocol() {
        // Both conform to `String` (raw value) + a std protocol — not a domain abstraction,
        // so the rule still fires.
        let issues = analyze(files: [
            "A.swift": "enum A: String, CaseIterable { case error, info, warning }",
            "B.swift": "enum B: String, Equatable { case error, info, warning }"
        ])
        #expect(issues.count == 2)
    }

    @Test
    func threeParallelEnumsFlagAll() {
        let issues = analyze(files: [
            "A.swift": "enum A { case red, green, blue }",
            "B.swift": "enum B { case red, green, blue }",
            "C.swift": "enum C { case red, green, blue }"
        ])
        #expect(issues.count == 3)
    }

    // MARK: - Does not fire

    @Test
    func sharedDomainProtocolSuppresses() {
        let issues = analyze(files: [
            "P.swift": "protocol Displayable {}",
            "A.swift": "enum A: Displayable { case error, info, warning }",
            "B.swift": "enum B: Displayable { case error, info, warning }"
        ])
        #expect(issues.isEmpty)
    }

    @Test
    func extensionBasedConformanceSuppresses() {
        // The shared protocol is adopted via a separate `extension`, not the enum's
        // inheritance clause — it must still count as "already unified".
        let issues = analyze(files: [
            "P.swift": "protocol Displayable {}",
            "A.swift": "enum A { case error, info, warning }\nextension A: Displayable {}",
            "B.swift": "enum B { case error, info, warning }\nextension B: Displayable {}"
        ])
        #expect(issues.isEmpty)
    }

    @Test
    func nestedExtensionConformanceSuppresses() {
        // Mirrors SwiftCompilerFlagStudio: one enum conforms inline, a nested enum
        // conforms via `extension Outer.Inner: P`.
        let issues = analyze(files: [
            "P.swift": "protocol SeverityDisplaying {}",
            "C.swift": "enum ConflictSeverity: SeverityDisplaying { case error, info, warning }",
            "V.swift": """
            struct ValidationResult { enum Severity { case error, info, warning } }
            extension ValidationResult.Severity: SeverityDisplaying {}
            """
        ])
        #expect(issues.isEmpty)
    }

    @Test
    func extensionConformanceOnOnlyOneMemberStillFires() {
        // Only A adopts the protocol; B shares nothing — they are not unified.
        let issues = analyze(files: [
            "P.swift": "protocol Displayable {}",
            "A.swift": "enum A { case error, info, warning }\nextension A: Displayable {}",
            "B.swift": "enum B { case error, info, warning }"
        ])
        #expect(issues.count == 2)
    }

    @Test
    func associatedValuesExcludeTheEnum() {
        // `A` has an associated value → not a plain tag enum → not catalogued, so the
        // remaining single `B` has no parallel peer.
        let issues = analyze(files: [
            "A.swift": "enum A { case error(Int), info, warning }",
            "B.swift": "enum B { case error, info, warning }"
        ])
        #expect(issues.isEmpty)
    }

    @Test
    func fewerThanThreeCasesIsBelowThreshold() {
        let issues = analyze(files: [
            "A.swift": "enum A { case on, off }",
            "B.swift": "enum B { case on, off }"
        ])
        #expect(issues.isEmpty)
    }

    @Test
    func differentCaseSetsDoNotCluster() {
        let issues = analyze(files: [
            "A.swift": "enum A { case error, info, warning }",
            "B.swift": "enum B { case low, medium, high }"
        ])
        #expect(issues.isEmpty)
    }

    @Test
    func singleEnumDoesNotFire() {
        let issues = analyze(files: [
            "A.swift": "enum A { case error, info, warning }"
        ])
        #expect(issues.isEmpty)
    }
}
