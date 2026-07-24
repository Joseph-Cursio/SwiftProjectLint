@testable import Core
import SwiftParser
@testable import SwiftProjectLintRules
import SwiftSyntax
import Testing

@Suite
struct DuplicateEnumMappingVisitorTests {

    private func analyze(files: [String: String]) -> [LintIssue] {
        var cache: [String: SourceFileSyntax] = [:]
        for (name, source) in files {
            cache[name] = Parser.parse(source: source)
        }
        let pattern = DuplicateEnumMapping().pattern
        let visitor = DuplicateEnumMappingVisitor(fileCache: cache)
        visitor.setPattern(pattern)

        for (name, ast) in cache {
            visitor.setFilePath(name)
            visitor.setSourceLocationConverter(SourceLocationConverter(fileName: name, tree: ast))
            visitor.walk(ast)
        }
        visitor.finalizeAnalysis()
        return visitor.detectedIssues.filter { $0.ruleName == .duplicateEnumMapping }
    }

    /// A `Tier → String` label switch over a parameter (not `self`), so it is not the enum's
    /// own centralized mapping.
    private func labelMap(_ function: String) -> String {
        """
        func \(function)(_ tier: Tier) -> String {
            switch tier {
            case .verified: return "Verified"
            case .strong: return "Strong"
            case .likely: return "Likely"
            }
        }
        """
    }

    // MARK: - Fires: two identical mappings, no centralized home

    @Test
    func twoIdenticalMappingsFireAtBothSites() throws {
        let issues = analyze(files: [
            "Tier.swift": "enum Tier { case verified, strong, likely }",
            "A.swift": labelMap("labelA"),
            "B.swift": labelMap("labelB")
        ])
        // Two sites is enough for the exact-value rule.
        #expect(issues.count == 2)
        let first = try #require(issues.first)
        #expect(first.message.contains("`Tier`"))
        #expect(first.message.contains("copied"))
    }

    // MARK: - Does not fire: only one mapping

    @Test
    func singleMappingDoesNotFire() {
        let issues = analyze(files: [
            "Tier.swift": "enum Tier { case verified, strong, likely }",
            "A.swift": labelMap("labelA")
        ])
        #expect(issues.isEmpty)
    }

    // MARK: - Does not fire: same cases, DIFFERENT values (the precision win)

    @Test
    func sameCasesDifferentValuesDoesNotFire() {
        let foreground = """
        func fg(_ sev: Sev) -> Color {
            switch sev {
            case .error: return .red
            case .warning: return .orange
            case .info: return .blue
            }
        }
        """
        let background = """
        func bg(_ sev: Sev) -> Color {
            switch sev {
            case .error: return .pink
            case .warning: return .yellow
            case .info: return .teal
            }
        }
        """
        let issues = analyze(files: [
            "Sev.swift": "enum Sev { case error, warning, info }",
            "FG.swift": foreground,
            "BG.swift": background
        ])
        // Same shape, different values — a real second mapping, not a copy. This is exactly the
        // case Scattered Enum Mapping's looser match would risk; value-matching leaves it alone.
        #expect(issues.isEmpty)
    }

    // MARK: - Fires: a duplicate of the enum's own `switch self` mapping

    @Test
    func duplicateOfCentralizedMappingIsPointedAtIt() throws {
        let centralized = """
        enum Tier {
            case verified, strong, likely
            var label: String {
                switch self {
                case .verified: return "Verified"
                case .strong: return "Strong"
                case .likely: return "Likely"
                }
            }
        }
        """
        let issues = analyze(files: [
            "Tier.swift": centralized,
            "Projection.swift": labelMap("humanReadableTier")
        ])
        // The `switch self` mapping is the canonical home; only the copy is reported.
        #expect(issues.count == 1)
        let issue = try #require(issues.first)
        #expect(issue.filePath == "Projection.swift")
        #expect(issue.message.contains("already on the type"))
        #expect(issue.message.contains("Tier.swift"))
    }

    // MARK: - Does not fire: too few cases (2-arm switches map by coincidence)

    @Test
    func twoArmSwitchesBelowLabelFloorDoNotFire() {
        let twoArm = { (function: String) in
            """
            func \(function)(_ flag: Flag) -> String {
                switch flag {
                case .on: return "On"
                case .off: return "Off"
                }
            }
            """
        }
        let issues = analyze(files: [
            "Flag.swift": "enum Flag { case on, off }",
            "A.swift": twoArm("a"),
            "B.swift": twoArm("b")
        ])
        #expect(issues.isEmpty)
    }

    // MARK: - Does not fire: non-value arms (arbitrary logic, not a mapping)

    @Test
    func nonValueArmsDoNotFire() {
        let logicSwitch = { (function: String) in
            """
            func \(function)(_ tier: Tier) -> String {
                switch tier {
                case .verified: return compute(tier)
                case .strong: return compute(tier)
                case .likely: return compute(tier)
                }
            }
            """
        }
        let issues = analyze(files: [
            "Tier.swift": "enum Tier { case verified, strong, likely }",
            "A.swift": logicSwitch("a"),
            "B.swift": logicSwitch("b")
        ])
        // `compute(tier)` is a lowercase-callee call, not a literal/member/initializer — the
        // switch is arbitrary logic, not a constant map, so it is not a mapping site.
        #expect(issues.isEmpty)
    }

    // MARK: - Two copies in the same file still fire (two distinct switches)

    @Test
    func twoCopiesInOneFileFire() {
        let both = labelMap("labelA") + "\n" + labelMap("labelB")
        let issues = analyze(files: [
            "Tier.swift": "enum Tier { case verified, strong, likely }",
            "Both.swift": both
        ])
        #expect(issues.count == 2)
    }
}
