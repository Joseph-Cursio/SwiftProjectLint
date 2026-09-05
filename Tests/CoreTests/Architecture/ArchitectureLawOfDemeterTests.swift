@testable import Core
import Foundation
import SwiftParser
@testable import SwiftProjectLintRules
import SwiftSyntax
import Testing

@Suite
struct ArchitectureLawOfDemeterTests {

    // MARK: - Helper

    private func analyzeSource(
        _ source: String,
        filePath: String = "TestFile.swift"
    ) -> [LintIssue] {
        let visitor = LawOfDemeterVisitor(patternCategory: .architecture)
        let syntax = Parser.parse(source: source)
        let converter = SourceLocationConverter(fileName: filePath, tree: syntax)
        visitor.setSourceLocationConverter(converter)
        visitor.setFilePath(filePath)
        visitor.walk(syntax)
        return visitor.detectedIssues
    }

    // MARK: - Detects violations (4+ levels)

    @Test func testDetectsFourLevelChain() throws {
        let source = """
        class Owner {
            func run() { let _ = manager.service.data.count }
        }
        """
        let issues = analyzeSource(source)
        let lodIssues = issues.filter { $0.ruleName == .lawOfDemeter }
        let issue = try #require(lodIssues.first)
        #expect(issue.message.contains("manager.service.data.count"))
    }

    @Test func testDetectsDeepChainInFunction() throws {
        let source = """
        class Display {
            let user = User()
            func show() -> String { return user.profile.address.street }
        }
        """
        let issues = analyzeSource(source)
        let lodIssues = issues.filter { $0.ruleName == .lawOfDemeter }
        let issue = try #require(lodIssues.first)
        #expect(issue.message.contains("user.profile.address.street"))
    }

    // MARK: - No violations (3 levels or fewer)

    @Test func testNoIssueForThreeLevelChain() {
        // a.b.c is idiomatic Swift — not flagged
        let source = """
        class Owner {
            func run() { let _ = manager.service.data }
        }
        """
        let issues = analyzeSource(source)
        let lodIssues = issues.filter { $0.ruleName == .lawOfDemeter }
        #expect(lodIssues.isEmpty)
    }

    @Test func testNoIssueForTwoLevelChain() {
        let source = """
        class Owner {
            func run() { let _ = manager.data }
        }
        """
        let issues = analyzeSource(source)
        let lodIssues = issues.filter { $0.ruleName == .lawOfDemeter }
        #expect(lodIssues.isEmpty)
    }

    @Test func testNoIssueForSelfChain() {
        let source = """
        class ViewModel {
            func run() { let _ = self.manager.service.data.count }
        }
        """
        let issues = analyzeSource(source)
        let lodIssues = issues.filter { $0.ruleName == .lawOfDemeter }
        #expect(lodIssues.isEmpty)
    }

    @Test func testNoIssueForSuperChain() {
        let source = """
        class Child: Parent {
            func run() { let _ = super.manager.data.value }
        }
        """
        let issues = analyzeSource(source)
        let lodIssues = issues.filter { $0.ruleName == .lawOfDemeter }
        #expect(lodIssues.isEmpty)
    }

    @Test func testFiresOnceForFiveLevelChain() {
        // a.b.c.d.e — should report exactly once from the outermost access
        let source = """
        class Owner {
            func run() { let _ = a.b.c.d.e }
        }
        """
        let issues = analyzeSource(source)
        let lodIssues = issues.filter { $0.ruleName == .lawOfDemeter }
        #expect(lodIssues.count == 1)
    }

    @Test func testNoIssueForFunctionCallChain() {
        // root is a FunctionCallExpr — SwiftUI modifier chain
        let source = """
        struct MyView: View {
            var body: some View {
                Text("hello").frame(width: 100).background(.red)
            }
        }
        """
        let issues = analyzeSource(source)
        let lodIssues = issues.filter { $0.ruleName == .lawOfDemeter }
        #expect(lodIssues.isEmpty)
    }

    // MARK: - Singleton / static accessor exemptions

    @Test func testNoIssueForFileManagerDefaultChain() {
        let source = """
        class Setup {
            func tempDir() -> URL {
                return FileManager.default.temporaryDirectory.appendingPathComponent("test")
            }
        }
        """
        let issues = analyzeSource(source)
        let lodIssues = issues.filter { $0.ruleName == .lawOfDemeter }
        #expect(lodIssues.isEmpty)
    }

    @Test func testNoIssueForProcessInfoChain() {
        let source = """
        class Guard {
            func isTesting() -> Bool {
                return ProcessInfo.processInfo.arguments.contains("--testing")
            }
        }
        """
        let issues = analyzeSource(source)
        let lodIssues = issues.filter { $0.ruleName == .lawOfDemeter }
        #expect(lodIssues.isEmpty)
    }

    // MARK: - Nested type / enum case exemptions

    @Test func testNoIssueForNestedTypeAccess() {
        let source = """
        class Validator {
            func check() -> String {
                return ValidationResult.ConfigField.optInRules.description
            }
        }
        """
        let issues = analyzeSource(source)
        let lodIssues = issues.filter { $0.ruleName == .lawOfDemeter }
        #expect(lodIssues.isEmpty)
    }

    @Test func testNoIssueForEnumAllCasesChain() {
        let source = """
        class Picker {
            func steps() {
                let _ = OnboardingManager.OnboardingStep.allCases.filter { $0.isRequired }
            }
        }
        """
        let issues = analyzeSource(source)
        let lodIssues = issues.filter { $0.ruleName == .lawOfDemeter }
        #expect(lodIssues.isEmpty)
    }

    // MARK: - Value transform exemptions

    @Test func testNoIssueForRawValueCapitalizedChain() {
        let source = """
        class Formatter {
            func label(for violation: Violation) -> String {
                return violation.severity.rawValue.capitalized
            }
        }
        """
        let issues = analyzeSource(source)
        let lodIssues = issues.filter { $0.ruleName == .lawOfDemeter }
        #expect(lodIssues.isEmpty)
    }

    // MARK: - Closure parameter exemptions

    @Test func testNoIssueForClosureParameterChain() {
        let source = """
        class Sorter {
            func sort(items: [Item]) -> [Item] {
                return items.sorted { $0.category.name.count < $1.category.name.count }
            }
        }
        """
        let issues = analyzeSource(source)
        let lodIssues = issues.filter { $0.ruleName == .lawOfDemeter }
        #expect(lodIssues.isEmpty)
    }

    // MARK: - Test file exemptions

    @Test func testNoIssueInTestFiles() {
        let source = """
        class OwnerTests {
            func test() { let _ = result.viewModel.searchText.isEmpty }
        }
        """
        let issues = analyzeSource(source, filePath: "OwnerTests.swift")
        let lodIssues = issues.filter { $0.ruleName == .lawOfDemeter }
        #expect(lodIssues.isEmpty)
    }

    // MARK: - Value-transform intermediate exemptions

    @Test func testNoIssueWhenDescriptionIsIntermediate() {
        // .description converts to String; trimmingCharacters is String manipulation, not object coupling
        let source = """
        class Chunker {
            func name(for node: ExtensionDeclSyntax) -> String {
                return node.extendedType.description.trimmingCharacters(in: .whitespaces)
            }
        }
        """
        let issues = analyzeSource(source)
        #expect(issues.contains { $0.ruleName == .lawOfDemeter } == false)
    }

    @Test func testNoIssueWhenTrimmedDescriptionIsIntermediate() {
        // .trimmedDescription is the SwiftSyntax shorthand; .contains is String manipulation
        let source = """
        class Parser {
            func check(arg: LabeledExprSyntax) -> Bool {
                return arg.expression.trimmedDescription.contains("expected")
            }
        }
        """
        let issues = analyzeSource(source)
        #expect(issues.contains { $0.ruleName == .lawOfDemeter } == false)
    }

    @Test func testNoIssueWhenColorIsIntermediate() {
        // .color maps enum to a SwiftUI Color value; .opacity is Color manipulation
        let source = """
        struct ConflictRow: View {
            let conflict: Conflict
            var body: some View {
                Color.clear.background(conflict.severity.color.opacity(0.06))
            }
        }
        """
        let issues = analyzeSource(source)
        #expect(issues.contains { $0.ruleName == .lawOfDemeter } == false)
    }

    @Test func testNoIssueForLowerBoundTerminal() {
        // .lowerBound extracts a value from a Range — terminal value-transform
        let source = """
        class Indexer {
            func start(for chunk: CodeChunk) -> Int {
                return chunk.lineRange.lowerBound
            }
        }
        """
        let issues = analyzeSource(source)
        #expect(issues.contains { $0.ruleName == .lawOfDemeter } == false)
    }

    @Test func testNoIssueForUpperBoundTerminal() {
        let source = """
        class Indexer {
            func end(for chunk: CodeChunk) -> Int {
                return chunk.lineRange.upperBound
            }
        }
        """
        let issues = analyzeSource(source)
        #expect(issues.contains { $0.ruleName == .lawOfDemeter } == false)
    }

    // MARK: - Still detects real violations

    @Test func testStillDetectsRealViolationInNonTestFile() {
        let source = """
        class Owner {
            func run() { let _ = manager.service.data.count }
        }
        """
        let issues = analyzeSource(source, filePath: "Owner.swift")
        let lodIssues = issues.filter { $0.ruleName == .lawOfDemeter }
        #expect(lodIssues.count == 1)
    }

    @Test func testStillDetectsViolationWhenVTAppearsAtDepth() {
        // a.b.c.description — vtIndex 3, not < 3, and terminal "description" at depth 3 → suppress
        // but a.b.c.d.description — vtIndex 4, not < 3, terminal at depth 4, no terminal exemption → flag
        let source = """
        class Owner {
            func run() { let _ = a.b.c.d.description }
        }
        """
        let issues = analyzeSource(source)
        #expect(issues.filter { $0.ruleName == .lawOfDemeter }.count == 1)
    }

    // MARK: - SwiftUI exemptions

    @Test func testNoIssueForBindingProjection() {
        let source = """
        class Editor {
            func setup() {
                let name = $viewModel.user.name.wrappedValue
            }
        }
        """
        let issues = analyzeSource(source)
        #expect(issues.contains { $0.ruleName == .lawOfDemeter } == false)
    }

    @Test func testNoIssueForEnvironmentRoot() {
        let source = """
        class ThemeManager {
            func color() -> String {
                return environment.theme.color.name
            }
        }
        """
        let issues = analyzeSource(source)
        #expect(issues.contains { $0.ruleName == .lawOfDemeter } == false)
    }

    @Test func testNoIssueForGeometryAccess() {
        let source = """
        class Layout {
            func width(of proxy: GeometryProxy) -> CGFloat {
                return proxy.frame.size.width
            }
        }
        """
        let issues = analyzeSource(source)
        #expect(issues.contains { $0.ruleName == .lawOfDemeter } == false)
    }

    @Test func testNoIssueForNavigatorRoot() {
        let source = """
        class Flow {
            func navigate() {
                coordinator.router.stack.count
            }
        }
        """
        let issues = analyzeSource(source)
        #expect(issues.contains { $0.ruleName == .lawOfDemeter } == false)
    }
}

/// One finding per reach-through, not per occurrence.
///
/// Measured before this existed: five sort comparators in SwiftInferProperties produced **48
/// findings for one missing `Comparable` conformance**, and eleven DTO-flattening constructors in
/// SwiftAssist produced eleven for zero problems. Re-run over that same pre-refactor source with
/// collapsing, the repository reports **40 instead of 90**.
///
/// The count was never describing something a reader would act on that many times, and it inverted
/// the priority: the largest cluster was the easiest fix — one conformance — while the smallest
/// findings were the ones that needed judgement.
@Suite("Law of Demeter counts reach-throughs, not occurrences")
struct LawOfDemeterCollapsingTests {
    private func analyze(_ source: String) -> [LintIssue] {
        let visitor = LawOfDemeterVisitor(patternCategory: .architecture)
        let syntax = Parser.parse(source: source)
        visitor.setSourceLocationConverter(
            SourceLocationConverter(fileName: "TestFile.swift", tree: syntax)
        )
        visitor.setFilePath("TestFile.swift")
        visitor.walk(syntax)
        return visitor.detectedIssues.filter { $0.ruleName == RuleIdentifier.lawOfDemeter }
    }

    @Test("a comparator reaching into one target four times reports once")
    func repeatedReachIntoOneTargetCollapses() {
        // The shape that produced 48 findings for one conformance. All four chains reach into
        // `location`, and the fix is a single `Comparable` on its type.
        let issues = analyze("""
        func lessThan(_ lhs: Pair, _ rhs: Pair) -> Bool {
            if lhs.member.location.file != rhs.member.location.file {
                return lhs.member.location.file < rhs.member.location.file
            }
            return lhs.member.location.line < rhs.member.location.line
        }
        """)
        #expect(issues.count == 1)
        #expect(issues.first?.message.contains("location") == true)
    }

    @Test("the same target in a different declaration is a different problem")
    func separateDeclarationsReportSeparately() {
        // Two functions each need their own fix applied, even when the target is the same, so
        // collapsing is per declaration rather than per file.
        #expect(analyze("""
        func first(_ lhs: Pair, _ rhs: Pair) -> Bool {
            lhs.member.location.file < rhs.member.location.file
        }
        func second(_ lhs: Pair, _ rhs: Pair) -> Bool {
            lhs.member.location.line < rhs.member.location.line
        }
        """).count == 2)
    }

    @Test("different targets in one declaration report separately")
    func distinctTargetsAreNotMerged() {
        // Collapsing must not hide a second, unrelated reach-through: `location` and `owner` are
        // different encapsulations on different types. (`signature` would not do here — it is on
        // the framework-API exemption list and never fires, which is how the first draft of this
        // test passed for the wrong reason.)
        let issues = analyze("""
        func describe(_ item: Item) -> String {
            let a = item.member.location.file
            let b = item.member.owner.name
            return a + b
        }
        """)
        #expect(issues.count == 2)
    }

    @Test("chains reached through different roots into one target still collapse")
    func lhsAndRhsAreOneProblem() {
        // `lhs` and `rhs` are the same shape. Keying on the root would split one fix in two, which
        // is what made the comparator clusters look like eight problems instead of one.
        #expect(analyze("""
        func compare(_ lhs: Pair, _ rhs: Pair) -> Bool {
            lhs.member.location.file < rhs.member.location.file
        }
        """).count == 1)
    }

    @Test("the message names the target, not the root")
    func messageNamesTheEncapsulationTarget() {
        // The fix goes on the penultimate hop's type. Naming the root sent the reader to `lhs`.
        let issues = analyze("""
        func compare(_ lhs: Pair, _ rhs: Pair) -> Bool {
            lhs.member.location.file < rhs.member.location.file
        }
        """)
        #expect(issues.first?.suggestion?.contains("'location'") == true)
    }
}
