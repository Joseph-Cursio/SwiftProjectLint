@testable import Core
import SwiftParser
@testable import SwiftProjectLintRules
import SwiftSyntax
import Testing

@Suite
struct SharedDomainEnumFieldVisitorTests {

    private func analyze(files: [String: String]) -> [LintIssue] {
        var cache: [String: SourceFileSyntax] = [:]
        for (name, source) in files {
            cache[name] = Parser.parse(source: source)
        }
        let pattern = SharedDomainEnumField().pattern
        let visitor = SharedDomainEnumFieldVisitor(fileCache: cache)
        visitor.setPattern(pattern)

        for (name, ast) in cache {
            visitor.setFilePath(name)
            visitor.setSourceLocationConverter(SourceLocationConverter(fileName: name, tree: ast))
            visitor.walk(ast)
        }
        visitor.finalizeAnalysis()
        return visitor.detectedIssues.filter { $0.ruleName == .sharedDomainEnumField }
    }

    /// Three sibling types each holding the same project-declared enum field, with no
    /// common protocol — the canonical "extract a marker protocol" case (the real
    /// `IssueSeverity` cluster that motivated the rule). One issue per participating type.
    @Test
    func threeTypesSharingProjectEnumFieldFlags() throws {
        let issues = analyze(files: [
            "Severity.swift": """
            enum IssueSeverity { case error, warning, info }
            """,
            "Conflict.swift": """
            struct SettingConflict {
                let severity: IssueSeverity
                let title: String
            }
            """,
            "Simulation.swift": """
            struct SimulationIssue {
                let severity: IssueSeverity
                let message: String
            }
            """,
            "Validation.swift": """
            struct ValidationIssue {
                let severity: IssueSeverity
                let detail: String
            }
            """
        ])

        #expect(issues.count == 3)
        #expect(issues.allSatisfy { $0.message.contains("severity") })
        #expect(issues.allSatisfy { $0.message.contains("IssueSeverity") })
        let issue = try #require(issues.first { $0.message.contains("SimulationIssue") })
        #expect(issue.suggestion?.contains("IssueSeverity") == true)
    }

    /// Two types are coincidence-prone; the rule needs at least three before suggesting
    /// an abstraction.
    @Test
    func twoTypesBelowThresholdClean() {
        let issues = analyze(files: [
            "Severity.swift": "enum IssueSeverity { case error, warning }",
            "A.swift": "struct Alpha { let severity: IssueSeverity }",
            "B.swift": "struct Beta { let severity: IssueSeverity }"
        ])

        #expect(issues.isEmpty)
    }

    /// The discriminator that keeps the rule quiet: a shared field of a *framework or
    /// primitive* type (`String`, `Int`, `UUID`) is not a domain axis. Only
    /// project-declared enums count, so `id: String` across three types is ignored.
    @Test
    func sharedPrimitiveFieldIgnored() {
        let issues = analyze(files: [
            "A.swift": "struct Alpha { let id: String }",
            "B.swift": "struct Beta { let id: String }",
            "C.swift": "struct Gamma { let id: String }"
        ])

        #expect(issues.isEmpty)
    }

    /// Already abstracted: when every clustered type conforms to a protocol that
    /// declares the shared property, the abstraction exists and nothing is suggested.
    @Test
    func fieldAlreadyCoveredByProtocolClean() {
        let issues = analyze(files: [
            "Severity.swift": """
            enum IssueSeverity { case error, warning }
            protocol Ranked { var severity: IssueSeverity { get } }
            """,
            "A.swift": "struct Alpha: Ranked { let severity: IssueSeverity }",
            "B.swift": "struct Beta: Ranked { let severity: IssueSeverity }",
            "C.swift": "struct Gamma: Ranked { let severity: IssueSeverity }"
        ])

        #expect(issues.isEmpty)
    }

    /// The same enum under *different property names* can't be unified into one protocol
    /// requirement, so it does not cluster — the key is (property name, enum type).
    @Test
    func sameEnumDifferentNamesClean() {
        let issues = analyze(files: [
            "Severity.swift": "enum IssueSeverity { case error, warning }",
            "A.swift": "struct Alpha { let severity: IssueSeverity }",
            "B.swift": "struct Beta { let level: IssueSeverity }",
            "C.swift": "struct Gamma { let rank: IssueSeverity }"
        ])

        #expect(issues.isEmpty)
    }
}
