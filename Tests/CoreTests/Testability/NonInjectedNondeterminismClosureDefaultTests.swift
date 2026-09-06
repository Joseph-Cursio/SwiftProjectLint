@testable import Core
import Foundation
import SwiftParser
@testable import SwiftProjectLintRules
import SwiftSyntax
import Testing

/// A parameter default is the seam whether it hands over the value or the capability that reads it.
///
/// The rule used to stop the default-value walk at any closure, so `clock: () -> Date = { Date() }`
/// was reported — the exact shape this rule's documentation offers as the fix. The corpus is what
/// showed the cost: three sites across two repositories carried a hand-written
/// `swiftprojectlint:disable:next` for this rule, each with a comment beside it saying the same
/// thing, and none of them had been traced back to the rule.
///
/// The line held here is `defaultValue`, not "is a closure". A closure argument at a call site is
/// still reported: `items.map { Date() }` runs immediately, and `queue.async { stamp = Date() }`
/// runs later with nothing able to substitute it. Only a parameter guarantees substitutability.
@Suite("A closure parameter default is an injection seam")
struct NonInjectedNondeterminismClosureDefaultTests {

    private func analyze(_ source: String) -> [LintIssue] {
        let visitor = NonInjectedNondeterminismVisitor(patternCategory: .testability)
        let syntax = Parser.parse(source: source)
        visitor.setSourceLocationConverter(
            SourceLocationConverter(fileName: "Logic.swift", tree: syntax)
        )
        visitor.setFilePath("Logic.swift")
        visitor.walk(syntax)
        return visitor.detectedIssues.filter { $0.ruleName == .nonInjectedNondeterminism }
    }

    @Test("a defaulted clock closure is not reported")
    func defaultedClockClosureIsNotReported() {
        #expect(analyze("struct S { init(now: @Sendable () -> Date = { Date() }) {} }").isEmpty)
    }

    @Test("attributes on the parameter type do not change the answer")
    func escapingAndSendableAreIrrelevant() {
        // The shape found in the corpus, verbatim apart from the surrounding type.
        #expect(analyze("""
        struct S {
            init(clock: @escaping @Sendable () -> Date = { Date() }) {}
        }
        """).isEmpty)
    }

    @Test("a multi-statement default closure is not reported either")
    func multiStatementDefaultClosureIsNotReported() {
        #expect(analyze("""
        func f(make: () -> UUID = { let id = UUID(); return id }) {}
        """).isEmpty)
    }

    @Test("a closure argument at a call site is still reported")
    func closureArgumentIsStillReported() {
        // Not a default, so nothing about it is substitutable: this runs, and the caller of `f`
        // has no say in what it reads.
        #expect(analyze("func f(_ xs: [Int]) -> [Date] { xs.map { _ in Date() } }").count == 1)
    }

    @Test("a stored closure property with a default is still reported")
    func storedClosurePropertyIsStillReported() {
        // `var maker: () -> Date = { Date() }` is a stored property, not a parameter. Whether it
        // can be replaced depends on an initialiser this rule cannot see from here.
        #expect(analyze("struct S { var maker: () -> Date = { Date() } }").count == 1)
    }

    @Test("a nested declaration's body inside a default is still reported")
    func bodyInsideADefaultIsStillReported() {
        // The walk stops at a function body: code that runs is not a value being handed over.
        #expect(analyze("""
        func outer(a: Int = 1) {
            func inner() -> Date { Date() }
        }
        """).count == 1)
    }
}
