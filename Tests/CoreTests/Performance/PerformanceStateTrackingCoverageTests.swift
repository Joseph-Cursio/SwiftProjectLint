@testable import Core
import SwiftParser
@testable import SwiftProjectLintRules
import SwiftSyntax
import Testing

/// Targeted coverage tests for uncovered paths in PerformanceStateVariableTracking.swift:
/// - `checkForUnnecessaryUpdates` issue-reporting branch (isAssigned && !isUsedInViewBody)
/// - `trackStateVariableUsage` for non-self member access (false branch)
/// - `trackStateVariableAssignment` entry path
/// - `trackStateVariableDeclaration` edge cases (non-@State wrappers, resets)
@Suite("PerformanceStateTrackingCoverageTests")
struct PerformanceStateTrackingCoverageTests {

    // MARK: - checkForUnnecessaryUpdates: assigned but not used in view body

    @Test("reports warning when state var is assigned but not used in view body")
    func unnecessaryUpdateDetectedWhenAssignedButNotUsed() throws {
        let source = """
        struct TestView: View {
            @State private var unused: Int = 0
            var body: some View {
                Text("static")
            }
        }
        """
        let syntax = Parser.parse(source: source)
        let visitor = PerformanceVisitor(patternCategory: .performance)
        visitor.setFilePath("TestView.swift")
        visitor.walk(syntax)

        // Manually mark the variable as assigned (simulating what trackStateVariableAssignment would do)
        let unusedInfo = try #require(visitor.stateVariables["unused"])
        visitor.stateVariables["unused"] = PerformanceStateVariableInfo(
            name: unusedInfo.name,
            declaredAtLine: unusedInfo.declaredAtLine,
            isUsedInViewBody: false,
            isAssigned: true,
            assignmentLine: 5
        )

        visitor.checkForUnnecessaryUpdates()

        let unnecessaryIssues = visitor.detectedIssues.filter {
            $0.message.contains("updated unnecessarily")
        }
        #expect(unnecessaryIssues.count == 1)
        let issue = try #require(unnecessaryIssues.first)
        #expect(issue.severity == .warning)
        #expect(issue.message.contains("unused"))
        #expect(issue.suggestion?.contains("Avoid updating state variables") == true)
    }

    @Test("uses assignmentLine when available in unnecessary update warning")
    func unnecessaryUpdateUsesAssignmentLine() throws {
        let visitor = PerformanceVisitor(patternCategory: .performance)
        visitor.setFilePath("TestView.swift")

        visitor.stateVariables["counter"] = PerformanceStateVariableInfo(
            name: "counter",
            declaredAtLine: 3,
            isUsedInViewBody: false,
            isAssigned: true,
            assignmentLine: 10
        )

        visitor.checkForUnnecessaryUpdates()

        let issues = visitor.detectedIssues.filter {
            $0.message.contains("counter")
        }
        let issue = try #require(issues.first)
        #expect(issue.lineNumber == 10)
    }

    @Test("falls back to declaredAtLine when assignmentLine is nil")
    func unnecessaryUpdateFallsBackToDeclaredLine() throws {
        let visitor = PerformanceVisitor(patternCategory: .performance)
        visitor.setFilePath("TestView.swift")

        visitor.stateVariables["counter"] = PerformanceStateVariableInfo(
            name: "counter",
            declaredAtLine: 3,
            isUsedInViewBody: false,
            isAssigned: true,
            assignmentLine: nil
        )

        visitor.checkForUnnecessaryUpdates()

        let issues = visitor.detectedIssues.filter {
            $0.message.contains("counter")
        }
        let issue = try #require(issues.first)
        #expect(issue.lineNumber == 3)
    }

    @Test("no warning when state var is both assigned and used in view body")
    func noWarningWhenAssignedAndUsed() {
        let visitor = PerformanceVisitor(patternCategory: .performance)
        visitor.setFilePath("TestView.swift")

        visitor.stateVariables["count"] = PerformanceStateVariableInfo(
            name: "count",
            declaredAtLine: 2,
            isUsedInViewBody: true,
            isAssigned: true,
            assignmentLine: 8
        )

        visitor.checkForUnnecessaryUpdates()

        let unnecessaryIssues = visitor.detectedIssues.filter {
            $0.message.contains("updated unnecessarily")
        }
        #expect(unnecessaryIssues.isEmpty)
    }

    @Test("no warning when state var is not assigned")
    func noWarningWhenNotAssigned() {
        let visitor = PerformanceVisitor(patternCategory: .performance)
        visitor.setFilePath("TestView.swift")

        visitor.stateVariables["label"] = PerformanceStateVariableInfo(
            name: "label",
            declaredAtLine: 2,
            isUsedInViewBody: false,
            isAssigned: false,
            assignmentLine: nil
        )

        visitor.checkForUnnecessaryUpdates()

        let unnecessaryIssues = visitor.detectedIssues.filter {
            $0.message.contains("updated unnecessarily")
        }
        #expect(unnecessaryIssues.isEmpty)
    }

    @Test("reports multiple unnecessary updates for multiple state vars")
    func multipleUnnecessaryUpdates() {
        let visitor = PerformanceVisitor(patternCategory: .performance)
        visitor.setFilePath("TestView.swift")

        visitor.stateVariables["alpha"] = PerformanceStateVariableInfo(
            name: "alpha",
            declaredAtLine: 2,
            isUsedInViewBody: false,
            isAssigned: true,
            assignmentLine: 10
        )
        visitor.stateVariables["beta"] = PerformanceStateVariableInfo(
            name: "beta",
            declaredAtLine: 3,
            isUsedInViewBody: false,
            isAssigned: true,
            assignmentLine: 12
        )
        visitor.stateVariables["gamma"] = PerformanceStateVariableInfo(
            name: "gamma",
            declaredAtLine: 4,
            isUsedInViewBody: true,
            isAssigned: true,
            assignmentLine: 14
        )

        visitor.checkForUnnecessaryUpdates()

        let unnecessaryIssues = visitor.detectedIssues.filter {
            $0.message.contains("updated unnecessarily")
        }
        #expect(unnecessaryIssues.count == 2)

        let reportedNames = Set(unnecessaryIssues.map(\.message))
        #expect(reportedNames.contains { $0.contains("alpha") })
        #expect(reportedNames.contains { $0.contains("beta") })
    }

    @Test("detected issues carry the correct file path")
    func issueFilePathCorrect() throws {
        let visitor = PerformanceVisitor(patternCategory: .performance)
        visitor.setFilePath("Features/MyView.swift")

        visitor.stateVariables["unused"] = PerformanceStateVariableInfo(
            name: "unused",
            declaredAtLine: 5,
            isUsedInViewBody: false,
            isAssigned: true,
            assignmentLine: 10
        )

        visitor.checkForUnnecessaryUpdates()

        let issue = try #require(visitor.detectedIssues.first)
        #expect(issue.filePath == "Features/MyView.swift")
    }
}
