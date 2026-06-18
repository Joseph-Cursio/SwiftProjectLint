@testable import Core
import SwiftParser
@testable import SwiftProjectLintRules
import SwiftSyntax
import Testing

@Suite
struct HoistableSequenceOperationVisitorTests {

    private func analyze(files: [String: String]) -> [LintIssue] {
        var cache: [String: SourceFileSyntax] = [:]
        for (name, source) in files {
            cache[name] = Parser.parse(source: source)
        }
        let pattern = HoistableSequenceOperation().pattern
        let visitor = HoistableSequenceOperationVisitor(fileCache: cache)
        visitor.setPattern(pattern)

        for (name, ast) in cache {
            visitor.setFilePath(name)
            visitor.setSourceLocationConverter(SourceLocationConverter(fileName: name, tree: ast))
            visitor.walk(ast)
        }
        visitor.finalizeAnalysis()
        return visitor.detectedIssues.filter { $0.ruleName == .hoistableSequenceOperation }
    }

    private static let rankedProtocol = """
    protocol Ranked {
        var category: String { get }
        var name: String { get }
    }
    """

    /// A multi-key sort closure (`{category,name}` ⊆ Ranked) repeated at two sites — the
    /// measured high-precision case. One issue per site, naming the hoist target.
    @Test
    func multiKeyClosureRepeatedHoists() throws {
        let issues = analyze(files: [
            "P.swift": Self.rankedProtocol,
            "A.swift": """
            func sortA(_ items: [Ranked]) -> [Ranked] {
                items.sorted { ($0.category, $0.name) < ($1.category, $1.name) }
            }
            """,
            "B.swift": """
            func sortB(_ items: [Ranked]) -> [Ranked] {
                items.sorted { ($0.category, $0.name) < ($1.category, $1.name) }
            }
            """
        ])

        #expect(issues.count == 2)
        #expect(issues.allSatisfy { $0.message.contains("Ranked") })
        #expect(issues.allSatisfy { $0.message.contains("category") && $0.message.contains("name") })
    }

    /// A single occurrence is not duplication — nothing to hoist and share.
    @Test
    func singleOccurrenceClean() {
        let issues = analyze(files: [
            "P.swift": Self.rankedProtocol,
            "A.swift": """
            func sortA(_ items: [Ranked]) -> [Ranked] {
                items.sorted { ($0.category, $0.name) < ($1.category, $1.name) }
            }
            """
        ])

        #expect(issues.isEmpty)
    }

    /// The precision gate: a single-member closure (`{name}`) is the dominant false-positive
    /// class — `name` subsets a protocol by coincidence. Below |S| >= 2, so it never fires,
    /// even repeated three times.
    @Test
    func singleMemberClosureNeverFires() {
        let issues = analyze(files: [
            "P.swift": Self.rankedProtocol,
            "A.swift": "func a(_ xs: [Ranked]) -> [Ranked] { xs.sorted { $0.name < $1.name } }",
            "B.swift": "func b(_ xs: [Ranked]) -> [Ranked] { xs.sorted { $0.name < $1.name } }",
            "C.swift": "func c(_ xs: [Ranked]) -> [Ranked] { xs.sorted { $0.name < $1.name } }"
        ])

        #expect(issues.isEmpty)
    }

    /// A two-member access set that matches no project protocol's requirements does not fire.
    @Test
    func memberSetMatchingNoProtocolClean() {
        let issues = analyze(files: [
            "P.swift": Self.rankedProtocol,
            "A.swift": "func a(_ xs: [T]) -> [T] { xs.sorted { ($0.alpha, $0.beta) < ($1.alpha, $1.beta) } }",
            "B.swift": "func b(_ xs: [T]) -> [T] { xs.sorted { ($0.alpha, $0.beta) < ($1.alpha, $1.beta) } }"
        ])

        #expect(issues.isEmpty)
    }

    /// Works for non-sort Sequence operations too: a repeated `filter` predicate touching two
    /// protocol requirements is equally hoistable.
    @Test
    func repeatedFilterPredicateHoists() {
        let issues = analyze(files: [
            "P.swift": Self.rankedProtocol,
            "A.swift": "func a(_ xs: [Ranked]) -> [Ranked] { xs.filter { $0.category == $0.name } }",
            "B.swift": "func b(_ xs: [Ranked]) -> [Ranked] { xs.filter { $0.category == $0.name } }"
        ])

        #expect(issues.count == 2)
    }
}
