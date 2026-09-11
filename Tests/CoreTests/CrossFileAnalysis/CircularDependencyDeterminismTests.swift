@testable import Core
import SwiftParser
@testable import SwiftProjectLintRules
import SwiftSyntax
import Testing

/// A cycle has two ends, and which one the rule reports must come from the code.
///
/// `typeReferences` is a `Dictionary`, so before the fix the walk reached `A ↔ B` from whichever
/// side the per-process hash seed happened to offer first — and that decided the reported file, the
/// reported line, and the order of the two names in the message. Five runs of one binary over one
/// unchanged repository gave three different answers.
///
/// These tests drive the visit order explicitly rather than relying on a dictionary, because the
/// claim is precisely that visit order does not reach the output.
///
/// **Two of the four only kill the defect about half the time, and that is the defect's own
/// signature rather than a weakness to fix.** Run against the unfixed visitor ten times:
/// `ordersSeveralCyclesStably` failed 10/10, `reportsTheSameEndWhicheverSideIsWalkedFirst` 6/10,
/// `reportsTheLexicographicallySmallerEnd` 5/10, and the weak-reference control 0/10. A test whose
/// subject is a per-process hash seed cannot be a decision on one run — the multi-cycle ordering is,
/// because four cycles give the seed too many ways to be wrong at once, and it is the test to keep if
/// only one survives. The other two are kept for what they say, not for their kill rate.
@Suite
struct CircularDependencyDeterminismTests {

    private func analyze(order: [(name: String, source: String)]) -> [LintIssue] {
        var cache: [String: SourceFileSyntax] = [:]
        for file in order {
            cache[file.name] = Parser.parse(source: file.source)
        }
        let visitor = CircularDependencyVisitor(fileCache: cache)
        visitor.setPattern(CircularDependency().pattern)

        for file in order {
            guard let ast = cache[file.name] else { continue }
            visitor.setFilePath(file.name)
            visitor.setSourceLocationConverter(
                SourceLocationConverter(fileName: file.name, tree: ast)
            )
            visitor.walk(ast)
        }
        visitor.finalizeAnalysis()
        return visitor.detectedIssues.filter { $0.ruleName == .circularDependency }
    }

    /// `Zebra` declared first and `Apple` declared first must report identically.
    private var pair: [(name: String, source: String)] {
        [
            ("Zebra.swift", """
            class Zebra {
                var apple: Apple
            }
            """),
            ("Apple.swift", """
            class Apple {
                var zebra: Zebra
            }
            """)
        ]
    }

    @Test func reportsTheSameEndWhicheverSideIsWalkedFirst() throws {
        let forward = analyze(order: pair)
        let reversed = analyze(order: pair.reversed())

        #expect(forward.count == 1)
        #expect(reversed.count == 1)

        let first = try #require(forward.first)
        let second = try #require(reversed.first)
        #expect(first.filePath == second.filePath)
        #expect(first.lineNumber == second.lineNumber)
        #expect(first.message == second.message)
    }

    /// The end reported is the lexicographically smaller name, which is the only tie-break available
    /// that is a fact about the code. Pinning *which* end keeps the previous test from passing on a
    /// rule that is merely consistently wrong — two identical reports at the wrong end satisfy it.
    @Test func reportsTheLexicographicallySmallerEnd() throws {
        let issue = try #require(analyze(order: pair).first)
        #expect(issue.filePath == "Apple.swift")
        #expect(issue.message == "Circular dependency detected: 'Apple' ↔ 'Zebra'")
    }

    /// Several cycles come out in a stable sequence, not only each at a stable place. The outer walk
    /// is over sorted keys for this reason; an unsorted one passes both tests above and still
    /// reorders a multi-cycle report between runs.
    @Test func ordersSeveralCyclesStably() {
        let files: [(name: String, source: String)] = [
            ("Delta.swift", """
            class Delta {
                var charlie: Charlie
            }
            """),
            ("Charlie.swift", """
            class Charlie {
                var delta: Delta
            }
            """),
            ("Bravo.swift", """
            class Bravo {
                var alpha: Alpha
            }
            """),
            ("Alpha.swift", """
            class Alpha {
                var bravo: Bravo
            }
            """)
        ]
        let forward = analyze(order: files).map(\.message)
        let reversed = analyze(order: files.reversed()).map(\.message)

        #expect(forward.count == 2)
        #expect(forward == reversed)
        #expect(forward == [
            "Circular dependency detected: 'Alpha' ↔ 'Bravo'",
            "Circular dependency detected: 'Charlie' ↔ 'Delta'"
        ])
    }

    /// A weak back-reference is still no cycle whichever side declares it, which is the one place
    /// where naming the smaller end could have changed a decision rather than only a location.
    @Test func aWeakBackReferenceIsStillNoCycleFromEitherSide() {
        let files: [(name: String, source: String)] = [
            ("Zebra.swift", """
            class Zebra {
                weak var apple: Apple?
            }
            """),
            ("Apple.swift", """
            class Apple {
                var zebra: Zebra
            }
            """)
        ]
        #expect(analyze(order: files).isEmpty)
        #expect(analyze(order: files.reversed()).isEmpty)
    }
}
