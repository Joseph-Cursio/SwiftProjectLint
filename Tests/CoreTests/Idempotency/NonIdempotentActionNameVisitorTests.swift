import SwiftParser
@testable import SwiftProjectLintIdempotencyRules
import SwiftProjectLintModels
import SwiftProjectLintVisitors
import SwiftSyntax
import Testing

@Suite
struct NonIdempotentActionNameVisitorTests {

    private func makeVisitor() -> NonIdempotentActionNameVisitor {
        let pattern = NonIdempotentActionName().pattern
        return NonIdempotentActionNameVisitor(pattern: pattern)
    }

    private func run(_ source: String) -> NonIdempotentActionNameVisitor {
        let visitor = makeVisitor()
        let sourceFile = Parser.parse(source: source)
        visitor.walk(sourceFile)
        return visitor
    }

    // MARK: - Positive cases (rule fires)

    @Test
    func setPrefixCaseThatIncrements_fires() throws {
        // The motivating `setBadge` shape: named `set…` but accumulates.
        let source = """
        func reduce() {
            switch action {
            case .setBadge:
                state.badge += 1
            }
        }
        """
        let visitor = run(source)
        #expect(visitor.detectedIssues.count == 1)
        let issue = try #require(visitor.detectedIssues.first)
        #expect(issue.ruleName == .nonIdempotentActionName)
        #expect(issue.severity == .warning)
        #expect(issue.message.contains("setBadge"))
        #expect(issue.message.contains("+="))
    }

    @Test
    func exactWitnessCaseThatToggles_fires() throws {
        // The `hide` shape: an exact witness name whose body toggles.
        let source = """
        switch action {
        case .hide:
            state.menu.toggle()
        }
        """
        let visitor = run(source)
        #expect(visitor.detectedIssues.count == 1)
        let issue = try #require(visitor.detectedIssues.first)
        #expect(issue.message.contains("hide"))
        #expect(issue.message.contains(".toggle()"))
    }

    @Test
    func payloadBindingCaseThatAccumulates_fires() {
        let source = """
        switch action {
        case let .setVolume(value):
            state.volume -= value
        }
        """
        let visitor = run(source)
        #expect(visitor.detectedIssues.count == 1)
    }

    // MARK: - Negative cases (rule does not fire)

    @Test
    func idempotentNamedCaseThatAssigns_doesNotFire() {
        // `set…` that assigns a fixed value IS idempotent — no finding.
        let source = """
        switch action {
        case .setEnabled:
            state.enabled = true
        case .dismiss:
            state.sheet = false
        }
        """
        let visitor = run(source)
        #expect(visitor.detectedIssues.isEmpty)
    }

    @Test
    func nonWitnessNamedCaseThatIncrements_doesNotFire() {
        // `increment` accumulates but doesn't claim idempotence by name.
        let source = """
        switch action {
        case .increment:
            state.count += 1
        }
        """
        let visitor = run(source)
        #expect(visitor.detectedIssues.isEmpty)
    }

    @Test
    func accumulationInsideEffectClosure_doesNotFire() {
        // A `+=` inside a returned effect closure is not the synchronous
        // state reduction, so it must not be flagged.
        let source = """
        switch action {
        case .dismiss:
            state.sheet = false
            return .run { _ in counter += 1 }
        }
        """
        let visitor = run(source)
        #expect(visitor.detectedIssues.isEmpty)
    }
}
