@testable import Core
import Foundation
import SwiftParser
@testable import SwiftProjectLintRules
import SwiftSyntax
import Testing

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

    private func analyze(_ source: String, filePath: String = "Logic.swift") -> [LintIssue] {
        let visitor = PureClosureCandidateVisitor(patternCategory: .testability)
        let syntax = Parser.parse(source: source)
        visitor.setSourceLocationConverter(
            SourceLocationConverter(fileName: filePath, tree: syntax)
        )
        visitor.setFilePath(filePath)
        visitor.walk(syntax)
        return visitor.detectedIssues.filter { $0.ruleName == .pureClosureCandidate }
    }

    // MARK: - The motivating case

    @Test("a filter predicate that captures a mutable var is still a candidate")
    func filterCapturingMutableStateIsCandidate() throws {
        // The capture is the whole point. `currentPath` is a `var` on the enclosing type, and that
        // says nothing about this closure: lift the body into
        // `isImmediateChild(_ path: String, of parent: String)` and the capture becomes a
        // parameter. Refusing captured state would refuse the best finding this rule has — this is
        // the bug site.
        let issues = analyze("""
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
        let issues = analyze("""
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
        #expect(analyze("func recent() { let recent = files.sorted { $0.date > $1.date } }").isEmpty)
        #expect(analyze("func ordered() { let ordered = names.sorted { $0 < $1 } }").isEmpty)
    }

    @Test("a non-strict comparator is flagged — it is not even irreflexive")
    func nonStrictComparatorIsFlagged() {
        // The size floor cannot catch this one: it is the *shortest* a comparator gets, and it is
        // wrong. `<=` is reflexive, so it is not a strict weak ordering, and `sorted(by:)` is within
        // its rights to crash on it.
        let issues = analyze("func ordered() { let ordered = files.sorted { $0.name <= $1.name } }")

        #expect(issues.count == 1)
        #expect(issues.first?.message.contains("strict weak ordering") == true)
    }

    @Test("a comparator over two keys is flagged")
    func multiKeyComparatorIsFlagged() {
        // The classic way to break transitivity, and it fits on one line.
        let issues = analyze("""
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
        let issues = analyze("""
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
        #expect(analyze("""
        func total() {
            let flags = items.map { item in
                runningTotal += item.amount
                return item.isValid
            }
        }
        """).isEmpty)
    }

    // MARK: - Predicates: the decision has to be one that can be got wrong

    @Test("a predicate that only surfaces a stored Bool decides nothing")
    func plainBooleanReadIsNotFlagged() {
        // Nothing is being decided here, only surfaced. A stored property cannot disagree with
        // itself, so there is no law to state and nothing to generate inputs against.
        #expect(analyze("func active() { let active = items.filter { $0.isEnabled } }").isEmpty)
        #expect(analyze("func shown() { let shown = items.filter { !$0.isHidden } }").isEmpty)
        #expect(analyze("func folders() { let folders = items.filter { $0.file.isFolder } }").isEmpty)
    }

    @Test("an equality predicate is identity, not a decision")
    func plainEqualityIsNotFlagged() {
        // `removeAll { $0 == fileURL }` means "remove this element" and nothing more. Equatable
        // already guarantees everything there is to guarantee, so there is no law left to state and
        // no off-by-one for a generator to find.
        #expect(analyze("func drop() { selected.removeAll { $0 == fileURL } }").isEmpty)
        #expect(analyze("func busy() { let busy = status.values.contains { $0 == .uploading } }")
            .isEmpty)
        #expect(analyze("func others() { let others = files.filter { $0.path != parent } }").isEmpty)
    }

    @Test("a relational predicate is a decision, and still a candidate")
    func relationalPredicateIsFlagged() {
        // Unlike `==`, a threshold or an ordering is exactly the decision that comes out one boundary
        // wrong. `>` or `>=`? `updated` before `created`, or after?
        #expect(analyze("func full() { let full = items.filter { $0.count > 0 } }").count == 1)
    }

    @Test("a one-line predicate with a rule in it is a candidate")
    func compoundPredicateIsFlagged() {
        // The bug the old size floor allowed through. This is one statement — so the floor of two
        // dropped it — and it is one off-by-one from wrong. Exactly the lesson the comparators
        // taught, which had not been applied to predicates.
        let issues = analyze("""
        func children() {
            let children = files.filter { $0.path.hasPrefix(parent) && $0.path != parent }
        }
        """)

        #expect(issues.count == 1)
        #expect(issues.first?.message.contains("predicate") == true)
    }

    @Test("a one-line predicate reached through a call is a candidate")
    func callShapedPredicateIsFlagged() {
        // Errs towards firing, symmetrically with the comparators: the analyser cannot see that the
        // call is total, and the interesting predicates in real code are call-shaped — every locale
        // bug lives in one.
        let issues = analyze("""
        func matching() {
            let matching = files.filter { $0.name.localizedCaseInsensitiveContains(query) }
        }
        """)

        #expect(issues.count == 1)
    }

    @Test("a one-line predicate comparing two keys is a candidate")
    func comparingPredicateIsFlagged() {
        #expect(analyze("func stale() { let stale = items.filter { $0.updated < $0.created } }")
            .count == 1)
    }

    @Test("min and max take comparators too, and the free ordering still applies")
    func freeOrderingHoldsAcrossComparatorOperations() {
        #expect(analyze("func fewest() { let fewest = items.min { $0.count < $1.count } }").isEmpty)
    }

    @Test("a transform with logic in it is a candidate")
    func transformWithLogicIsCandidate() {
        let issues = analyze("""
        func labels() {
            let labels = files.map { file in
                let size = Double(file.byteCount) / 1_000_000
                return "\\(file.name) (\\(size) MB)"
            }
        }
        """)

        #expect(issues.count == 1)
        #expect(issues.first?.message.contains("transform") == true)
    }

    @Test("a reducer's combine step is a candidate")
    func reducerIsCandidate() {
        let issues = analyze("""
        func total() {
            let total = items.reduce(Money.zero) { running, item in
                let taxed = item.price * (1 + item.taxRate)
                return running + taxed
            }
        }
        """)

        #expect(issues.count == 1)
        #expect(issues.first?.message.contains("associative") == true)
    }

    @Test("a closure doing I/O is refused")
    func impureClosureIsRefused() {
        #expect(analyze("""
        func log() {
            items.filter { item in
                print(item)
                return item.isValid
            }
        }
        """).isEmpty)
    }

    @Test("a one-line map projection is not worth a finding")
    func trivialProjectionIsNotFlagged() {
        // `map { $0.name }` is a projection, not a property. Naming it buys nothing, and a rule
        // that fires on every `map` in the codebase teaches people to switch the category off.
        #expect(analyze("func names() { let names = items.map { $0.name } }").isEmpty)
    }

    @Test("a closure not passed to a collection operation is ignored")
    func nonCollectionClosureIsIgnored() {
        // `Task { }` takes a closure too. A closure run for its effects is not a property waiting
        // to be named, and the operation list is a fixed one for exactly that reason.
        #expect(analyze("""
        func start() {
            Task {
                let value = compute()
                return value
            }
        }
        """).isEmpty)
    }

    @Test("test files are skipped")
    func testFilesAreSkipped() {
        #expect(analyze("""
        func fetch() {
            let children = allFiles.filter { file in
                let relative = file.path
                return relative.count <= 1
            }
        }
        """, filePath: "LogicTests.swift").isEmpty)
    }

    // MARK: - The symbol is a location

    /// The symbol names the enclosing **member**, because that is the only thing a reader can
    /// navigate to. `filter` names the operation, not the code, and every `filter` in a codebase
    /// would share it — a consumer narrowing to `filter` narrows to nothing.
    @Test("the symbol is the enclosing function, not the collection operation")
    func symbolIsTheEnclosingFunction() {
        let issues = analyze("""
        func fetchLocalFiles() {
            files = allFiles.sorted { lhs, rhs in
                if lhs.isFolder != rhs.isFolder { return lhs.isFolder }
                return lhs.name < rhs.name
            }
        }
        """)

        #expect(issues.first?.symbol == "fetchLocalFiles")
    }

    /// **A local binding is stepped over.** Written naively the parent walk stops at the nearest
    /// `VariableDeclSyntax` — which here is the local `let`, yielding the symbol `immediateChildren`:
    /// a name that exists nowhere a consumer can look up, and that changes the instant someone
    /// renames a local. This is the exact shape of `fetchLocalFiles`, and the naive walk got it
    /// wrong.
    @Test("a closure bound to a local `let` is still named for the enclosing function")
    func localBindingIsNotTheSymbol() {
        let issues = analyze("""
        func fetchLocalFiles() {
            let immediateChildren = allFiles.filter { file in
                let relativePath = file.path.replacingOccurrences(of: currentPath, with: "")
                return relativePath.split(separator: "/").count <= 1
            }
            print(immediateChildren)
        }
        """)

        #expect(issues.first?.symbol == "fetchLocalFiles")
        #expect(issues.first?.symbol != "immediateChildren")
    }

    /// A computed property is a member with a body, and the predicate hiding in it is as extractable
    /// as one inside a `func`. Refusing it because it is spelled `var` would be a distinction the
    /// reader does not care about.
    @Test("a closure inside a computed property is named for the property")
    func computedPropertyIsTheSymbol() {
        let issues = analyze("""
        struct Model {
            var filteredFiles: [File] {
                files.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
            }
        }
        """)

        #expect(issues.first?.symbol == "filteredFiles")
    }
}
