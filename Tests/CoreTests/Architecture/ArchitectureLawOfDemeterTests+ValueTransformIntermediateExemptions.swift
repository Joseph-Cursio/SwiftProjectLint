@testable import Core
import Foundation
import SwiftParser
@testable import SwiftProjectLintRules
import SwiftSyntax
import Testing

extension ArchitectureLawOfDemeterTests {
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
            func run() { let _ = manager.service.data.owner }
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
