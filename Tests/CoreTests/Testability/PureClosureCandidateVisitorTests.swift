@testable import Core
import Foundation
import SwiftParser
@testable import SwiftProjectLintRules
import SwiftSyntax
import Testing

/// Drives the visitor over `source` and returns just this rule's findings.
///
/// At file scope rather than inside the suite: it is the suite's only helper, and keeping it
/// out of the type keeps the body within `type_body_length` as tests accumulate. Call sites
/// read identically either way.
///
/// `projectFunctions` is what `ProjectLinter`'s pre-scan injects in a real run — the functions
/// this codebase declares, which is the one fact that tells a closure still hiding logic from one
/// merely forwarding to a function the reader already extracted.
/// Shared with `ForwardingCallKeyTests`, which was split out of this file. Internal rather than
/// duplicated: two copies of a harness are how two suites come to disagree about what they measure.
func analyzeClosureCandidates(
    _ source: String,
    filePath: String = "Logic.swift",
    projectFunctions: Set<String> = []
) -> [LintIssue] {
    let visitor = PureClosureCandidateVisitor(patternCategory: .testability)
    visitor.knownProjectFunctions = projectFunctions
    let syntax = Parser.parse(source: source)
    visitor.setSourceLocationConverter(
        SourceLocationConverter(fileName: filePath, tree: syntax)
    )
    visitor.setFilePath(filePath)
    visitor.walk(syntax)
    return visitor.detectedIssues.filter { $0.ruleName == .pureClosureCandidate }
}

/// The property test hiding inside a closure.
///
/// `pureFunctionCandidate` can only point at a *declaration*, and a great deal of the pure logic in
/// real Swift has none. A `filter` predicate or a `sorted(by:)` comparator written inline is a pure
/// function in everything but syntax; being anonymous is the only thing standing between it and a
/// property test. The linter had nothing to say about them, so neither did the reader.
///
/// The case this rule was built for is `MacCloudViewModel.fetchLocalFiles`, which hides two pure
/// functions in two closures — and one of them contains a real bug (`replacingOccurrences` strips
/// *every* match, not just the leading one, so a grandchild is listed as an immediate child). It
/// went unnoticed because there was nothing to write a test against.
@Suite("Pure closures are property-test candidates")
struct PureClosureCandidateVisitorTests {

    // MARK: - The motivating case

    @Test("a filter predicate that captures a mutable var is still a candidate")
    func filterCapturingMutableStateIsCandidate() {
        // The capture is the whole point. `currentPath` is a `var` on the enclosing type, and that
        // says nothing about this closure: lift the body into
        // `isImmediateChild(_ path: String, of parent: String)` and the capture becomes a
        // parameter. Refusing captured state would refuse the best finding this rule has — this is
        // the bug site.
        let issues = analyzeClosureCandidates("""
        func fetch() {
            let children = allFiles.filter { file in
                let relativePath = file.path.replacingOccurrences(of: currentPath, with: "")
                return relativePath.split(separator: "/").count <= 1
            }
        }
        """)

        #expect(issues.count == 1)
        #expect(issues.first?.message.contains("filter") == true)
        #expect(issues.first?.suggestion?.contains("Anything it captures becomes a parameter") == true)
    }

    @Test("a comparator earns the strict-weak-ordering law by name")
    func comparatorNamesItsLaw() throws {
        let issues = analyzeClosureCandidates("""
        func fetch() {
            files = children.sorted { file1, file2 in
                if file1.isFolder != file2.isFolder { return file1.isFolder }
                return file1.name < file2.name
            }
        }
        """)

        let finding = try #require(issues.first)
        // The law is the reason to bother extracting it. A comparator that is not a strict weak
        // ordering can crash `sorted(by:)`, and no example test tells you which triple broke it.
        #expect(finding.message.contains("strict weak ordering"))
    }

    // MARK: - Comparators: the ordering has to be worth stating

    @Test("a comparator on one key in its natural order gets its ordering for free")
    func singleKeyNaturalOrderingIsNotFlagged() {
        // `$0.date > $1.date` inherits its ordering from `Comparable` and cannot be got wrong. There
        // is no law left to state, so there is nothing to name — and a rule that fires on every
        // `sorted` in the codebase is the noise that teaches people to switch the category off.
        #expect(analyzeClosureCandidates("func recent() { let recent = files.sorted { $0.date > $1.date } }").isEmpty)
        #expect(analyzeClosureCandidates("func ordered() { let ordered = names.sorted { $0 < $1 } }").isEmpty)
    }

    @Test("a non-strict comparator is flagged — it is not even irreflexive")
    func nonStrictComparatorIsFlagged() {
        // The size floor cannot catch this one: it is the *shortest* a comparator gets, and it is
        // wrong. `<=` is reflexive, so it is not a strict weak ordering, and `sorted(by:)` is within
        // its rights to crash on it.
        let issues = analyzeClosureCandidates("func ordered() { let ordered = files.sorted { $0.name <= $1.name } }")

        #expect(issues.count == 1)
        #expect(issues.first?.message.contains("strict weak ordering") == true)
    }

    @Test("a comparator over two keys is flagged")
    func multiKeyComparatorIsFlagged() {
        // The classic way to break transitivity, and it fits on one line.
        let issues = analyzeClosureCandidates("""
        func ordered() {
            let ordered = tasks.sorted { $0.priority > $1.priority || $0.name < $1.name }
        }
        """)

        #expect(issues.count == 1)
    }

    @Test("a comparator whose key is a call is flagged")
    func comparatorOverAComputedKeyIsFlagged() {
        // The ordering is only free when the key is plain stored access. `localizedCaseInsensitive`
        // ordering is locale-dependent, and the syntax cannot tell us it is total.
        let issues = analyzeClosureCandidates("""
        func ordered() {
            let ordered = files.sorted {
                $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
            }
        }
        """)

        #expect(issues.count == 1)
    }

    // MARK: - Not candidates

    @Test("a closure that writes to a capture is refused")
    func mutatingClosureIsRefused() {
        // Its job IS the side effect; no extraction rescues it, because lifting the body out would
        // not turn `runningTotal` into a parameter.
        //
        // Deliberately a `map` and not a `forEach`: `forEach` is not on the operation list at all, so
        // a `forEach` here would be refused before purity was ever consulted, and this test would
        // pass without exercising the thing it names.
        #expect(analyzeClosureCandidates("""
        func total() {
            let flags = items.map { item in
                runningTotal += item.amount
                return item.isValid
            }
        }
        """).isEmpty)
    }
}
