import Testing
import Foundation
import SwiftSyntax
import SwiftParser
@testable import Core
@testable import SwiftProjectLintRules

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

    @Test func testNoIssueForThreeLevelChain() throws {
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

    @Test func testNoIssueForTwoLevelChain() throws {
        let source = """
        class Owner {
            func run() { let _ = manager.data }
        }
        """
        let issues = analyzeSource(source)
        let lodIssues = issues.filter { $0.ruleName == .lawOfDemeter }
        #expect(lodIssues.isEmpty)
    }

    @Test func testNoIssueForSelfChain() throws {
        let source = """
        class ViewModel {
            func run() { let _ = self.manager.service.data.count }
        }
        """
        let issues = analyzeSource(source)
        let lodIssues = issues.filter { $0.ruleName == .lawOfDemeter }
        #expect(lodIssues.isEmpty)
    }

    @Test func testNoIssueForSuperChain() throws {
        let source = """
        class Child: Parent {
            func run() { let _ = super.manager.data.value }
        }
        """
        let issues = analyzeSource(source)
        let lodIssues = issues.filter { $0.ruleName == .lawOfDemeter }
        #expect(lodIssues.isEmpty)
    }

    @Test func testFiresOnceForFiveLevelChain() throws {
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

    @Test func testNoIssueForFunctionCallChain() throws {
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

    @Test func testNoIssueForFileManagerDefaultChain() throws {
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

    @Test func testNoIssueForProcessInfoChain() throws {
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

    @Test func testNoIssueForNestedTypeAccess() throws {
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

    @Test func testNoIssueForEnumAllCasesChain() throws {
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

    @Test func testNoIssueForRawValueCapitalizedChain() throws {
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

    @Test func testNoIssueForClosureParameterChain() throws {
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

    @Test func testNoIssueInTestFiles() throws {
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
        #expect(issues.filter { $0.ruleName == .lawOfDemeter }.isEmpty)
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
        #expect(issues.filter { $0.ruleName == .lawOfDemeter }.isEmpty)
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
        #expect(issues.filter { $0.ruleName == .lawOfDemeter }.isEmpty)
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
        #expect(issues.filter { $0.ruleName == .lawOfDemeter }.isEmpty)
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
        #expect(issues.filter { $0.ruleName == .lawOfDemeter }.isEmpty)
    }

    // MARK: - Still detects real violations

    @Test func testStillDetectsRealViolationInNonTestFile() throws {
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
        #expect(issues.filter { $0.ruleName == .lawOfDemeter }.isEmpty)
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
        #expect(issues.filter { $0.ruleName == .lawOfDemeter }.isEmpty)
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
        #expect(issues.filter { $0.ruleName == .lawOfDemeter }.isEmpty)
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
        #expect(issues.filter { $0.ruleName == .lawOfDemeter }.isEmpty)
    }
}
