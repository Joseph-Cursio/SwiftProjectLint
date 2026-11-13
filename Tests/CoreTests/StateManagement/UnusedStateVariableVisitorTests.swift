import SwiftParser
import SwiftProjectLintModels
@testable import SwiftProjectLintRules
import SwiftProjectLintVisitors
import SwiftSyntax
import Testing

@Suite
struct UnusedStateVariableVisitorTests {

    private func issues(_ source: String) -> [LintIssue] {
        let tree = Parser.parse(source: source)
        let visitor = UnusedStateVariableVisitor(pattern: UnusedStateVariable().pattern)
        visitor.setFilePath("View.swift")
        visitor.setSourceLocationConverter(SourceLocationConverter(fileName: "View.swift", tree: tree))
        visitor.walk(tree)
        return visitor.detectedIssues.filter { $0.ruleName == .unusedStateVariable }
    }

    private func view(_ members: String) -> String {
        """
        import SwiftUI
        struct CounterView: View {
            \(members)
            var body: some View { Text("Hello") }
        }
        """
    }

    // MARK: - Reported

    @Test("a private @State named nowhere else is reported at its declaration")
    func reportsUnusedPrivateState() throws {
        let found = issues(view("@State private var count = 0"))
        let issue = try #require(found.first)
        #expect(found.count == 1)
        #expect(issue.lineNumber == 3)
        #expect(issue.message == "State variable 'count' is declared but never used")
    }

    @Test("fileprivate, @StateObject, qualified @SwiftUI.State and each binding of a list count")
    func reportsEveryFileLocalOwningShape() {
        #expect(issues(view("@State fileprivate var count = 0")).count == 1)
        #expect(issues(view("@StateObject private var model = Model()")).count == 1)
        #expect(issues(view("@SwiftUI.State private var count = 0")).count == 1)
        #expect(issues(view("@State private var first = 0, second = 1")).count == 2)
    }

    // MARK: - Not reported

    @Test("a read, a $ binding, _ storage, a key path or an interpolation is a use")
    func everySpellingOfTheNameIsAUse() {
        let uses = [
            "var label: String { String(count) }",
            "var toggle: some View { Stepper(\"\", value: $count) }",
            "init() { _count = State(initialValue: 1) }",
            "var path: KeyPath<CounterView, Int> { \\.count }",
            "var text: String { \"\\(count)\" }",
        ]
        for use in uses {
            #expect(issues(view("@State private var count = 0\n    \(use)")).isEmpty, "use: \(use)")
        }
    }

    @Test("a use in a same-file extension counts")
    func extensionInTheSameFileCounts() {
        let source = view("@State private var count = 0") + """

        extension CounterView {
            func bump() { count += 1 }
        }
        """
        #expect(issues(source).isEmpty)
    }

    @Test("a backticked name is matched without its backticks")
    func backtickedNamesMatch() {
        #expect(issues(view("@State private var `default` = 0\n    var x: Int { `default` }")).isEmpty)
        #expect(issues(view("@State private var `default` = 0")).count == 1)
    }

    @Test("internal, public and private(set) properties are skipped: another file could read them")
    func widerAccessIsSkipped() {
        #expect(issues(view("@State var count = 0")).isEmpty)
        #expect(issues(view("@State public var count = 0")).isEmpty)
        #expect(issues(view("@State private(set) var count = 0")).isEmpty)
    }

    @Test("other wrappers and plain properties are not this rule's")
    func otherWrappersAreSkipped() {
        #expect(issues(view("@Binding private var count: Int")).isEmpty)
        #expect(issues(view("@Environment(\\.dismiss) private var dismiss")).isEmpty)
        #expect(issues(view("private var count = 0")).isEmpty)
    }
}
