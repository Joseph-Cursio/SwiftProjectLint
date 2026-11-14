import SwiftParser
import SwiftProjectLintModels
@testable import SwiftProjectLintRules
import SwiftProjectLintVisitors
import SwiftSyntax
import Testing

/// A replaceable stored closure property is the same seam as a closure parameter default.
///
/// SwiftMutator's `World` is a dependency-injection container whose `var now: Now = { Date() }` is
/// the production default of a clock that is already injected, and the rule told it to inject the
/// source. A `var` member holding a closure is substitutable by whoever holds the value, and in a
/// struct without a hand-written initialiser the memberwise initialiser takes it as a defaulted
/// parameter, so it is exempt for the reason a parameter default is.
@Suite("A replaceable stored closure property is an injection seam")
struct NondeterminismStoredClosureSeamTests {

    private func analyze(_ source: String) -> [LintIssue] {
        let visitor = NonInjectedNondeterminismVisitor(patternCategory: .testability)
        let syntax = Parser.parse(source: source)
        visitor.setSourceLocationConverter(SourceLocationConverter(fileName: "Logic.swift", tree: syntax))
        visitor.setFilePath("Logic.swift")
        visitor.walk(syntax)
        return visitor.detectedIssues.filter { $0.ruleName == .nonInjectedNondeterminism }
    }

    @Test("a replaceable closure property's default is not reported", arguments: [
        // The corpus shape, verbatim apart from the container.
        "typealias Now = @Sendable () -> Date\nstruct World: Sendable { var now: Now = { Date() } }",
        "struct S { var maker: () -> Date = { Date() } }",
        "final class Env { var uuid: () -> UUID = { UUID() } }",
        "struct S { public var now = { Date() } }",
        "enum Current { static var now: () -> Date = { Date() } }",
        "struct S { var roll: () -> Int = { let n = Int.random(in: 1...6); return n } }",
    ])
    func replaceableClosureDefaultIsNotReported(source: String) {
        #expect(analyze(source).isEmpty)
    }

    /// Each of these is reported exactly once: none of them can be replaced from outside the
    /// declaration, so none is a seam.
    @Test("a closure nothing outside can replace is still reported", arguments: [
        // A `let` with an initial value is fixed for every instance.
        "struct S { let now: () -> Date = { Date() } }",
        // A test cannot write it.
        "struct S { private var now: () -> Date = { Date() } }",
        "struct S { fileprivate var now: () -> Date = { Date() } }",
        "struct S { private(set) var now: () -> Date = { Date() } }",
        // A local is replaceable only by the code around it.
        "func f() -> Date { var now: () -> Date = { Date() }; return now() }",
        // Called: the property stores a `Date`, which is a value.
        "final class C { lazy var stamp: Date = { Date() }() }",
        // A provider built from a closure: the closure is an argument.
        "struct P { static var live = DateProvider { Date() } }",
        // Observed rather than plain stored: refused, which fails toward the report.
        "struct S { var now: () -> Date = { Date() } { didSet {} } }",
        // A body between the read and the seam is code that runs.
        "struct S { var make: () -> Date = { func inner() -> Date { Date() }; return inner() } }",
    ])
    func unreplaceableClosureIsStillReported(source: String) {
        #expect(analyze(source).count == 1)
    }

    @Test("a stored value that is not a closure is still reported")
    func storedValueIsStillReported() {
        #expect(analyze("struct S { var stamp: Date = Date() }").count == 1)
    }
}
