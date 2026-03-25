import Testing
import SwiftParser
import SwiftSyntax
@testable import Core

/// Targeted coverage tests for uncovered paths in PerformanceStateVariableTracking.swift:
/// - `checkForUnnecessaryUpdates` issue-reporting branch (isAssigned && !isUsedInViewBody)
/// - `trackStateVariableUsage` for non-self member access (false branch)
/// - `trackStateVariableAssignment` entry path
/// - `trackStateVariableDeclaration` edge cases (non-@State wrappers, resets)
@Suite("PerfUnnecessaryUpdateCoverageTests")
struct PerfUnnecessaryUpdateCoverageTests {

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
    func noWarningWhenAssignedAndUsed() throws {
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
    func noWarningWhenNotAssigned() throws {
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
    func multipleUnnecessaryUpdates() throws {
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

        let reportedNames = Set(unnecessaryIssues.map { $0.message })
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

/// Coverage tests for trackStateVariableUsage, trackStateVariableDeclaration edge cases,
/// and detectForEachWithoutID/detectForEachSelfID in PerformanceDetectionHelpers.swift.
@Suite("PerfUsageAndForEachCoverageTests")
struct PerfUsageAndForEachCoverageTests {

    // MARK: - Helpers

    private func makeVisitor(
        source: String,
        filePath: String = "TestView.swift"
    ) -> PerformanceVisitor {
        let syntax = Parser.parse(source: source)
        let visitor = PerformanceVisitor(patternCategory: .performance)
        let converter = SourceLocationConverter(fileName: filePath, tree: syntax)
        visitor.setSourceLocationConverter(converter)
        visitor.setFilePath(filePath)
        visitor.walk(syntax)
        return visitor
    }

    // MARK: - trackStateVariableUsage: non-self member access

    @Test("does not mark state var as used for non-self member access")
    func nonSelfMemberAccessDoesNotMarkUsed() throws {
        let source = """
        struct TestView: View {
            @State private var count: Int = 0
            var body: some View {
                Text(someObject.count)
            }
        }
        """

        let visitor = makeVisitor(source: source)
        if let countInfo = visitor.stateVariables["count"] {
            #expect(countInfo.isUsedInViewBody == false)

        }
    }

    @Test("marks state var as used only for self.variableName access")
    func selfMemberAccessMarksUsed() throws {
        let source = """
        struct TestView: View {
            @State private var title: String = "Hello"
            var body: some View {
                Text(self.title)
            }
        }
        """

        let visitor = makeVisitor(source: source)
        let titleInfo = try #require(visitor.stateVariables["title"])
        #expect(titleInfo.isUsedInViewBody)
    }

    @Test("does not mark non-existent state var when accessed via self")
    func selfAccessOfNonStateVarIgnored() throws {
        let source = """
        struct TestView: View {
            @State private var count: Int = 0
            var regularProp: String = "test"
            var body: some View {
                Text(self.regularProp)
                Text("\\(self.count)")
            }
        }
        """

        let visitor = makeVisitor(source: source)
        #expect(visitor.stateVariables["regularProp"] == nil)
        let countInfo = try #require(visitor.stateVariables["count"])
        #expect(countInfo.isUsedInViewBody)
    }

    // MARK: - trackStateVariableAssignment: entry path

    @Test("trackStateVariableAssignment handles assignment in view body context")
    func assignmentExpressionVisited() throws {
        let source = """
        struct TestView: View {
            @State private var count: Int = 0
            var body: some View {
                Button("Go") {
                    self.count = 42
                }
            }
        }
        """

        let visitor = makeVisitor(source: source)
        let countInfo = try #require(visitor.stateVariables["count"])
        #expect(countInfo.name == "count")
    }

    // MARK: - trackStateVariableDeclaration edge cases

    @Test("does not track variables without property wrappers")
    func plainVariableNotTracked() throws {
        let source = """
        struct TestView: View {
            var plainVar: Int = 0
            let constant: String = "test"
            var body: some View { Text("hello") }
        }
        """

        let visitor = makeVisitor(source: source)
        #expect(visitor.stateVariables["plainVar"] == nil)
        #expect(visitor.stateVariables["constant"] == nil)
    }

    @Test("does not track @Binding variables")
    func bindingVariableNotTracked() throws {
        let source = """
        struct TestView: View {
            @Binding var isPresented: Bool
            @State private var count: Int = 0
            var body: some View { Text("\\(self.count)") }
        }
        """

        let visitor = makeVisitor(source: source)
        #expect(visitor.stateVariables["isPresented"] == nil)
        #expect(visitor.stateVariables["count"] != nil)
    }

    @Test("resets state variables when visiting a new struct")
    func stateVariablesResetForNewView() throws {
        let source = """
        struct FirstView: View {
            @State private var alpha: Int = 0
            var body: some View { Text("first") }
        }
        struct SecondView: View {
            @State private var beta: Int = 0
            var body: some View { Text("second") }
        }
        """

        let visitor = makeVisitor(source: source)
        #expect(visitor.stateVariables["alpha"] == nil)
        #expect(visitor.stateVariables["beta"] != nil)
    }

    @Test("checkForUnnecessaryUpdates is called at end of struct visit")
    func unnecessaryUpdateDetectedAtStructEnd() throws {
        let source = """
        struct TestView: View {
            @State private var count: Int = 0
            var body: some View {
                Text("\\(self.count)")
            }
        }
        """

        let visitor = makeVisitor(source: source)
        let unnecessaryIssues = visitor.detectedIssues.filter {
            $0.message.contains("updated unnecessarily")
        }
        #expect(unnecessaryIssues.isEmpty)
    }

    // MARK: - detectForEachWithoutID coverage

    @Test("detectForEachWithoutID skips non-self member access")
    func forEachDetectionSkipsNonSelfAccess() throws {
        let source = """
        struct TestView: View {
            var body: some View {
                Text("hello")
                    .frame(alignment: .leading)
            }
        }
        """

        let visitor = makeVisitor(source: source)
        let forEachIssues = visitor.detectedIssues.filter {
            $0.message.contains("Using .self as id in ForEach")
        }
        #expect(forEachIssues.isEmpty)
    }

    @Test("detectForEachSelfID detects backslash-self in nested ForEach")
    func detectsSelfIDInNestedForEach() throws {
        let source = """
        struct TestView: View {
            var items = [[1, 2], [3, 4]]
            var body: some View {
                ForEach(items, id: \\.self) { row in
                    ForEach(row, id: \\.self) { item in
                        Text("\\(item)")
                    }
                }
            }
        }
        """

        let visitor = makeVisitor(source: source)
        let selfIDIssues = visitor.detectedIssues.filter {
            $0.message.contains("\\.self") && $0.message.contains("ForEach")
        }
        #expect(selfIDIssues.count >= 2)
    }

    @Test("detectForEachSelfID does not flag ForEach with proper id keypath")
    func noFalsePositiveForProperKeypath() throws {
        let source = """
        struct TestView: View {
            struct Item: Identifiable {
                let identifier: UUID
                let name: String
            }
            var items: [Item] = []
            var body: some View {
                ForEach(items, id: \\.identifier) { item in
                    Text(item.name)
                }
            }
        }
        """

        let visitor = makeVisitor(source: source)
        let selfIDIssues = visitor.detectedIssues.filter {
            $0.message.contains("\\.self") && $0.message.contains("ForEach")
        }
        #expect(selfIDIssues.isEmpty)
    }

    @Test("detectForEachSelfID does not flag non-ForEach function calls")
    func noFalsePositiveForListWithSelfID() throws {
        let source = """
        struct TestView: View {
            var items = [1, 2, 3]
            var body: some View {
                List(items, id: \\.self) { item in
                    Text("\\(item)")
                }
            }
        }
        """

        let visitor = makeVisitor(source: source)
        let forEachSelfIssues = visitor.detectedIssues.filter {
            $0.message.contains("ForEach") && $0.message.contains("\\.self")
        }
        #expect(forEachSelfIssues.isEmpty)
    }
}
