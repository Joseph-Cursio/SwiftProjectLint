@testable import Core
import SwiftParser
@testable import SwiftProjectLintRules
import SwiftSyntax
import Testing

@Suite
struct SubclassedForMockingVisitorTests {

    private func analyze(files: [String: String]) -> [LintIssue] {
        var cache: [String: SourceFileSyntax] = [:]
        for (name, source) in files {
            cache[name] = Parser.parse(source: source)
        }
        let pattern = SubclassedForMocking().pattern
        let visitor = SubclassedForMockingVisitor(fileCache: cache)
        visitor.setPattern(pattern)

        for (name, ast) in cache {
            visitor.setFilePath(name)
            visitor.setSourceLocationConverter(SourceLocationConverter(fileName: name, tree: ast))
            visitor.walk(ast)
        }
        visitor.finalizeAnalysis()
        return visitor.detectedIssues.filter { $0.ruleName == .subclassedForMocking }
    }

    @Test
    func flagsProductionClassSubclassedByMock() throws {
        let issues = analyze(files: [
            "WorkspaceAnalyzer.swift": """
            class WorkspaceAnalyzer {
                func analyze() { }
            }
            """,
            "Helpers.swift": """
            class MockWorkspaceAnalyzer: WorkspaceAnalyzer {
                override func analyze() { }
            }
            """
        ])

        #expect(issues.count == 1)
        let issue = try #require(issues.first)
        #expect(issue.message.contains("WorkspaceAnalyzer"))
        #expect(issue.message.contains("MockWorkspaceAnalyzer"))
        // Reported at the production class, not the mock.
        #expect(issue.filePath == "WorkspaceAnalyzer.swift")
    }

    @Test
    func flagsViaTestFileLocationWithoutMockPrefix() {
        let issues = analyze(files: [
            "ImpactSimulator.swift": """
            class ImpactSimulator {
                func simulate() { }
            }
            """,
            "ImpactSimulatorTests.swift": """
            class RecordingSimulator: ImpactSimulator {
                override func simulate() { }
            }
            """
        ])

        #expect(issues.contains { $0.message.contains("ImpactSimulator") })
    }

    @Test
    func noIssueWhenBaseAlreadyConformsToProtocol() {
        let issues = analyze(files: [
            "Analyzing.swift": "protocol WorkspaceAnalyzing { func analyze() }",
            "WorkspaceAnalyzer.swift": """
            class WorkspaceAnalyzer: WorkspaceAnalyzing {
                func analyze() { }
            }
            """,
            "Helpers.swift": """
            class MockWorkspaceAnalyzer: WorkspaceAnalyzer {
                override func analyze() { }
            }
            """
        ])

        #expect(issues.isEmpty)
    }

    @Test
    func noIssueWhenMirrorProtocolExists() {
        let issues = analyze(files: [
            "WorkspaceAnalyzerProtocol.swift": "protocol WorkspaceAnalyzerProtocol { func analyze() }",
            "WorkspaceAnalyzer.swift": """
            class WorkspaceAnalyzer {
                func analyze() { }
            }
            """,
            "Helpers.swift": """
            class MockWorkspaceAnalyzer: WorkspaceAnalyzer {
                override func analyze() { }
            }
            """
        ])

        #expect(issues.isEmpty)
    }

    @Test
    func noIssueForGenuineProductionSubclass() {
        let issues = analyze(files: [
            "BaseRow.swift": """
            class BaseRow {
                func render() { }
            }
            """,
            "FancyRow.swift": """
            class FancyRow: BaseRow {
                override func render() { }
            }
            """
        ])

        #expect(issues.isEmpty)
    }

    /// A production subclass whose name only *contains* a mock marker mid-word
    /// (`Mockingbird…` ⊃ `Mock`) is not a test double, so its base is not flagged.
    /// Guards against the old `hasPrefix("Mock")` check that matched `Mocking…`.
    @Test
    func productionSubclassWithMarkerMidNameDoesNotFlagBase() {
        let issues = analyze(files: [
            "ChartController.swift": """
            class ChartController {
                func render() { }
            }
            """,
            "MockingbirdController.swift": """
            class MockingbirdController: ChartController {
                override func render() { }
            }
            """
        ])

        #expect(issues.isEmpty)
    }

    @Test
    func reportsEachBaseOnceForMultipleMocks() {
        let issues = analyze(files: [
            "ImpactSimulator.swift": """
            class ImpactSimulator {
                func simulate() { }
            }
            """,
            "MockA.swift": "class MockSimulatorA: ImpactSimulator { override func simulate() { } }",
            "MockB.swift": "class MockSimulatorB: ImpactSimulator { override func simulate() { } }"
        ])

        let simulatorIssues = issues.filter { $0.message.contains("ImpactSimulator") }
        #expect(simulatorIssues.count == 1)
    }
}
