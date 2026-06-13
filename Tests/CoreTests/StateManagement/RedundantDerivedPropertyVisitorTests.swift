@testable import Core
import SwiftParser
@testable import SwiftProjectLintRules
import SwiftSyntax
import Testing

/// Tests for `RedundantDerivedPropertyVisitor`.
///
/// Flags a stored property assigned a string interpolation of its sibling state
/// fields (`state.fullName = "\(state.firstName) \(state.lastName)"`) — derived
/// state that should be a computed property. Motivated by a TCA state-consistency
/// review.
@Suite
struct RedundantDerivedPropertyVisitorTests {

    private func makeVisitor() -> RedundantDerivedPropertyVisitor {
        let pattern = RedundantDerivedProperty().pattern
        return RedundantDerivedPropertyVisitor(pattern: pattern)
    }

    private func runVisitor(_ visitor: RedundantDerivedPropertyVisitor, source: String) {
        let sourceFile = Parser.parse(source: source)
        visitor.walk(sourceFile)
    }

    // MARK: - Flagged

    @Test("Flags the fullName shape (interpolation of two siblings)")
    func detectsFullName() throws {
        let source = """
        func reduce() {
            state.fullName = "\\(state.firstName) \\(state.lastName)"
        }
        """
        let visitor = makeVisitor()
        runVisitor(visitor, source: source)

        #expect(visitor.detectedIssues.count == 1)
        let issue = try #require(visitor.detectedIssues.first)
        #expect(issue.ruleName == .redundantDerivedProperty)
        #expect(issue.severity == .info)
        #expect(issue.message.contains("fullName"))
    }

    @Test("Flags a derived path built from sibling fields")
    func detectsDerivedPath() {
        let source = """
        func reduce() {
            state.path = "\\(state.directory)/\\(state.filename)"
        }
        """
        let visitor = makeVisitor()
        runVisitor(visitor, source: source)
        #expect(visitor.detectedIssues.count == 1)
    }

    @Test("Flags a single-sibling derivation (greeting from state.name)")
    func detectsSingleSibling() {
        let source = """
        func reduce() {
            state.greeting = "Hello, \\(state.name)!"
        }
        """
        let visitor = makeVisitor()
        runVisitor(visitor, source: source)
        #expect(visitor.detectedIssues.count == 1)
    }

    // MARK: - Not flagged

    @Test("No issue for a constant string")
    func noIssueForConstant() {
        let source = """
        func reduce() {
            state.title = "Settings"
        }
        """
        let visitor = makeVisitor()
        runVisitor(visitor, source: source)
        #expect(visitor.detectedIssues.isEmpty)
    }

    @Test("No issue when interpolating a non-sibling (local) value")
    func noIssueForExternalInput() {
        let source = """
        func reduce() {
            state.greeting = "Hello, \\(name)!"
        }
        """
        let visitor = makeVisitor()
        runVisitor(visitor, source: source)
        #expect(visitor.detectedIssues.isEmpty)
    }

    @Test("No issue for a self-referential append")
    func noIssueForAppend() {
        let source = """
        func reduce() {
            state.log = "\\(state.log) \\(entry)"
        }
        """
        let visitor = makeVisitor()
        runVisitor(visitor, source: source)
        #expect(visitor.detectedIssues.isEmpty)
    }

    @Test("No issue for a numeric aggregate (out of scope by design)")
    func noIssueForNumericAggregate() {
        let source = """
        func reduce() {
            state.total = state.price + state.tax
        }
        """
        let visitor = makeVisitor()
        runVisitor(visitor, source: source)
        #expect(visitor.detectedIssues.isEmpty)
    }

    @Test("No issue when base differs between target and interpolation")
    func noIssueForDifferentBase() {
        let source = """
        func reduce() {
            state.fullName = "\\(other.firstName) \\(other.lastName)"
        }
        """
        let visitor = makeVisitor()
        runVisitor(visitor, source: source)
        #expect(visitor.detectedIssues.isEmpty)
    }
}
