import Foundation
import SwiftProjectLintModels
import Testing

extension PureFunctionCandidateVisitorTests {
    // MARK: - Instance methods
    //
    // These used to be refused as a category, on the grounds that "instance methods can read
    // mutable self". Some do. This one does not:
    //
    //     struct Calc { func add(_ a: Int, _ b: Int) -> Int { a + b } }
    //
    // and it was the old test's own fixture. Refusing the category to avoid the members of it that
    // are unsafe left the rule blind in an app, where almost all logic is instance methods — so the
    // seed manifest arrived empty on exactly the codebases the lint → infer loop is aimed at. The
    // question is now asked rather than assumed: what does the method actually read?

    @Test func suggestsInstanceMethodThatReadsNothingFromSelf() {
        let source = """
        struct Calc {
            var total = 0
            func add(_ a: Int, _ b: Int) -> Int { a + b }
        }
        """
        let issues = analyze(source)

        // `total` is mutable, but `add` never touches it: it is a function of its inputs.
        #expect(issues.count == 1)
        #expect(issues.first?.symbol == "add")
        #expect(issues.first?.message.contains("a function of its inputs") == true)
    }

    @Test func suggestsInstanceMethodThatReadsOnlyImmutableStoredState() {
        let source = """
        struct Pricer {
            let rate: Double
            func total(_ amount: Double) -> Double { amount * rate }
        }
        """
        let issues = analyze(source)

        // `self` is the input. The test has to build a Pricer, which is a chore, not an obstacle.
        #expect(issues.count == 1)
        #expect(issues.first?.message.contains("a function of `self` and its inputs") == true)
    }

    @Test func suggestsNullaryMethodOverImmutableStoredState() {
        // No parameters at all, and still a property subject: vary the value, not the arguments.
        let source = """
        struct Receipt {
            let amount: Double
            func formatted() -> String { String(amount) }
        }
        """
        let issues = analyze(source)

        #expect(issues.count == 1)
        #expect(issues.first?.symbol == "formatted")
    }

    @Test func ignoresInstanceMethodReadingMutableState() {
        // The case the old blanket refusal was actually aimed at. Two calls with the same argument
        // can return different answers, so it is a function of nothing a test can pin down.
        let source = """
        struct Counter {
            var count = 0
            func plus(_ n: Int) -> Int { count + n }
        }
        """
        #expect(analyze(source).isEmpty)
    }

    /// **Reversed by B9, and the old expectation is the bug it names.**
    ///
    /// This used to assert `.isEmpty`, on the reasoning that "a computed property can read anything
    /// at all, so reading one is not reading `self`." True of an *arbitrary* computed property;
    /// false of a **derived** one. `var derived: Int { raw * 2 }` reads a single `let` and is exactly
    /// as pure as it is — and refusing it meant the linter refused the very value type it had just
    /// told the reader to extract. The refusal is now made on what the getter actually reads, not on
    /// the fact that it has a getter.
    ///
    /// Selected by symbol rather than by position: `derived` is *itself* a candidate now that
    /// computed properties are seeded, and it precedes `scaled` in source order. That is the same
    /// judgement this test's own reasoning makes — a getter reading one `let` is as pure as the
    /// `let` — so the extra finding is the rule agreeing with itself, not noise to suppress.
    @Test func flagsInstanceMethodReadingDerivedState() throws {
        let issues = analyze("""
        struct Report {
            let raw: Int
            var derived: Int { raw * 2 }
            func scaled(_ n: Int) -> Int { derived * n }
        }
        """)
        let issue = try #require(issues.first { $0.message.contains("scaled") })
        #expect(issue.message.contains("scaled"))
        // And the derived property is a candidate in its own right.
        #expect(issues.contains { $0.message.contains("derived") })
    }

    /// The half of the old rule that was right, kept: a computed property whose getter reads a name
    /// this file cannot resolve may vary independently of the arguments, so a method reading it is
    /// not a function of `self`.
    @Test func ignoresInstanceMethodReadingUnresolvableComputedState() {
        #expect(analyze("""
        struct Report {
            let raw: Int
            var derived: Int { raw * hiddenGlobal }
            func scaled(_ n: Int) -> Int { derived * n }
        }
        """).contains { $0.message.contains("scaled") } == false)
    }

    @Test func ignoresInstanceMethodReadingAnUnresolvableIdentifier() {
        // `hidden` is declared in some other file, or is a global — this file cannot tell. Purity
        // is the bottom of the lattice and the most dangerous place to land wrongly, so doubt
        // refutes: under-suggesting costs a missed test, over-suggesting costs a generated test
        // that runs impure code and lies about the result.
        let source = """
        extension Widget {
            func scaled(_ n: Int) -> Int { hidden * n }
        }
        """
        #expect(analyze(source).isEmpty)
    }

    @Test func ignoresMutatingMethod() {
        let source = """
        struct Counter {
            var count = 0
            mutating func bump(_ n: Int) -> Int { count += n; return count }
        }
        """
        #expect(analyze(source).isEmpty)
    }

    @Test func suggestsExtensionMethodSeeingStoredStateFromThePrimaryDeclaration() {
        // The shape that matters most in real code: the logic lives in an extension, the stored
        // properties in the primary declaration. Gathering across the file is what lets the two
        // meet — an extension's own member block holds no stored properties at all.
        let source = """
        struct Pricer {
            let rate: Double
        }

        extension Pricer {
            func total(_ amount: Double) -> Double { amount * rate }
        }
        """
        let issues = analyze(source)

        #expect(issues.count == 1)
        #expect(issues.first?.symbol == "total")
    }

    @Test func ignoresTestFiles() {
        #expect(analyze("func add(_ a: Int, _ b: Int) -> Int { a + b }", filePath: "MathTests.swift").isEmpty)
    }
}
