@testable import Core
import SwiftParser
@testable import SwiftProjectLintRules
import SwiftSyntax
import Testing

@Suite
struct ScatteredEnumMappingVisitorTests {

    private func analyze(files: [String: String]) -> [LintIssue] {
        var cache: [String: SourceFileSyntax] = [:]
        for (name, source) in files {
            cache[name] = Parser.parse(source: source)
        }
        let pattern = ScatteredEnumMapping().pattern
        let visitor = ScatteredEnumMappingVisitor(fileCache: cache)
        visitor.setPattern(pattern)

        for (name, ast) in cache {
            visitor.setFilePath(name)
            visitor.setSourceLocationConverter(SourceLocationConverter(fileName: name, tree: ast))
            visitor.walk(ast)
        }
        visitor.finalizeAnalysis()
        return visitor.detectedIssues.filter { $0.ruleName == .scatteredEnumMapping }
    }

    /// One mapping switch per file, no `Color`-shaped wording — uses a parameter subject
    /// (`switch sev`) so none is treated as the enum's own centralized mapping.
    private func scatteredColorMap(_ function: String) -> String {
        """
        func \(function)(_ sev: Sev) -> Color {
            switch sev {
            case .error: return .red
            case .warning: return .orange
            case .info: return .blue
            }
        }
        """
    }

    // MARK: - Fires: three scattered copies, no centralized mapping

    @Test
    func threeScatteredCopiesFlagsEachSite() throws {
        let issues = analyze(files: [
            "Sev.swift": "enum Sev { case error, warning, info }",
            "A.swift": scatteredColorMap("colorA"),
            "B.swift": scatteredColorMap("colorB"),
            "C.swift": scatteredColorMap("colorC")
        ])
        #expect(issues.count == 3)
        let first = try #require(issues.first)
        #expect(first.message.contains("`Sev`"))
        #expect(first.message.contains("no centralized mapping"))
        // Implicit-member kind reports the shared member set.
        #expect(first.message.contains(".blue"))
    }

    // MARK: - Fires: a centralized mapping exists → "re-implements" wording

    @Test
    func centralizedMappingChangesMessage() throws {
        let centralized = """
        import SwiftUI
        enum Sev {
            case error, warning, info
            var color: Color {
                switch self {
                case .error: return .red
                case .warning: return .orange
                case .info: return .blue
                }
            }
        }
        """
        let issues = analyze(files: [
            "Sev.swift": centralized,
            "A.swift": scatteredColorMap("colorA"),
            "B.swift": scatteredColorMap("colorB"),
            "C.swift": scatteredColorMap("colorC")
        ])
        // The centralized `self` switch is not counted as scatter — 3 scattered remain.
        #expect(issues.count == 3)
        let first = try #require(issues.first)
        #expect(first.message.contains("re-implements"))
        #expect(first.message.contains("already exists on the type"))
    }

    // MARK: - Twin enums note

    @Test
    func twinEnumsAddConsolidationNote() throws {
        let issues = analyze(files: [
            "Sev.swift": "enum Sev { case error, warning, info }",
            "Status.swift": "enum Status { case error, warning, info }",
            "A.swift": scatteredColorMap("colorA"),
            "B.swift": scatteredColorMap("colorB"),
            "C.swift": scatteredColorMap("colorC")
        ])
        let first = try #require(issues.first)
        let suggestion = try #require(first.suggestion)
        #expect(suggestion.contains("identical cases"))
        #expect(suggestion.contains("Sev"))
        #expect(suggestion.contains("Status"))
    }

    // MARK: - Does not fire

    @Test
    func twoCopiesIsBelowThreshold() {
        let issues = analyze(files: [
            "A.swift": scatteredColorMap("colorA"),
            "B.swift": scatteredColorMap("colorB")
        ])
        #expect(issues.isEmpty)
    }

    @Test
    func threeCopiesInOneFileNeedsTwoFiles() {
        let single = """
        \(scatteredColorMap("colorA"))
        \(scatteredColorMap("colorB"))
        \(scatteredColorMap("colorC"))
        """
        let issues = analyze(files: ["All.swift": single])
        #expect(issues.isEmpty)
    }

    @Test
    func twoCaseSwitchIsBelowLabelThreshold() {
        // Only two `.case` labels — below the minimum of three.
        func twoCase(_ function: String) -> String {
            """
            func \(function)(_ flag: Toggle) -> Color {
                switch flag {
                case .on: return .green
                case .off: return .red
                }
            }
            """
        }
        let issues = analyze(files: [
            "A.swift": twoCase("a"),
            "B.swift": twoCase("b"),
            "C.swift": twoCase("c")
        ])
        #expect(issues.isEmpty)
    }

    @Test
    func nonUniformReturnKindsDoNotMap() {
        // Mixed arm kinds (implicit member + string literal) are not a uniform mapping.
        func mixed(_ function: String) -> String {
            """
            func \(function)(_ sev: Sev) -> Any {
                switch sev {
                case .error: return .red
                case .warning: return "warn"
                case .info: return 3
                }
            }
            """
        }
        let issues = analyze(files: [
            "A.swift": mixed("a"),
            "B.swift": mixed("b"),
            "C.swift": mixed("c")
        ])
        #expect(issues.isEmpty)
    }

    @Test
    func multiStatementArmsAreNotPureMapping() {
        // An arm with a side-effecting statement before the value is not a pure map.
        func impure(_ function: String) -> String {
            """
            func \(function)(_ sev: Sev) -> Color {
                switch sev {
                case .error:
                    print("err")
                    return .red
                case .warning: return .orange
                case .info: return .blue
                }
            }
            """
        }
        let issues = analyze(files: [
            "A.swift": impure("a"),
            "B.swift": impure("b"),
            "C.swift": impure("c")
        ])
        #expect(issues.isEmpty)
    }

    @Test
    func onlyCentralizedMappingDoesNotFire() {
        // A single centralized mapping with no scattered copies is the desired state.
        let centralized = """
        import SwiftUI
        enum Sev {
            case error, warning, info
            var color: Color {
                switch self {
                case .error: return .red
                case .warning: return .orange
                case .info: return .blue
                }
            }
        }
        """
        let issues = analyze(files: ["Sev.swift": centralized])
        #expect(issues.isEmpty)
    }
}
