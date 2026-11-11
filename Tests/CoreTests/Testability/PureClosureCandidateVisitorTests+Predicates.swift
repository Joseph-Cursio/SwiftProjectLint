import Foundation
import SwiftProjectLintModels
import Testing

extension PureClosureCandidateVisitorTests {
    // MARK: - Predicates: the decision has to be one that can be got wrong

    @Test("a predicate that only surfaces a stored Bool decides nothing")
    func plainBooleanReadIsNotFlagged() {
        // Nothing is being decided here, only surfaced. A stored property cannot disagree with
        // itself, so there is no law to state and nothing to generate inputs against.
        #expect(analyzeClosureCandidates("func active() { let active = items.filter { $0.isEnabled } }").isEmpty)
        #expect(analyzeClosureCandidates("func shown() { let shown = items.filter { !$0.isHidden } }").isEmpty)
        #expect(analyzeClosureCandidates("func folders() { let folders = items.filter { $0.file.isFolder } }").isEmpty)
    }

    @Test("an equality predicate is identity, not a decision")
    func plainEqualityIsNotFlagged() {
        // `removeAll { $0 == fileURL }` means "remove this element" and nothing more. Equatable
        // already guarantees everything there is to guarantee, so there is no law left to state and
        // no off-by-one for a generator to find.
        #expect(analyzeClosureCandidates("func drop() { selected.removeAll { $0 == fileURL } }").isEmpty)
        #expect(analyzeClosureCandidates("func busy() { let busy = status.values.contains { $0 == .uploading } }")
            .isEmpty)
        #expect(analyzeClosureCandidates("func others() { let others = files.filter { $0.path != parent } }").isEmpty)
    }

    @Test("a relational predicate is a decision, and still a candidate")
    func relationalPredicateIsFlagged() {
        // Unlike `==`, a threshold or an ordering is exactly the decision that comes out one boundary
        // wrong. `>` or `>=`? `updated` before `created`, or after?
        #expect(analyzeClosureCandidates("func full() { let full = items.filter { $0.count > 0 } }").count == 1)
    }

    @Test("a one-line predicate with a rule in it is a candidate")
    func compoundPredicateIsFlagged() {
        // The bug the old size floor allowed through. This is one statement — so the floor of two
        // dropped it — and it is one off-by-one from wrong. Exactly the lesson the comparators
        // taught, which had not been applied to predicates.
        let issues = analyzeClosureCandidates("""
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
        let issues = analyzeClosureCandidates("""
        func matching() {
            let matching = files.filter { $0.name.localizedCaseInsensitiveContains(query) }
        }
        """)

        #expect(issues.count == 1)
    }

    @Test("a one-line predicate comparing two keys is a candidate")
    func comparingPredicateIsFlagged() {
        #expect(analyzeClosureCandidates("func stale() { let stale = items.filter { $0.updated < $0.created } }")
            .count == 1)
    }

    @Test("min and max take comparators too, and the free ordering still applies")
    func freeOrderingHoldsAcrossComparatorOperations() {
        #expect(analyzeClosureCandidates("func fewest() { let fewest = items.min { $0.count < $1.count } }").isEmpty)
    }

    @Test("a transform with logic in it is a candidate")
    func transformWithLogicIsCandidate() {
        let issues = analyzeClosureCandidates("""
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
        let issues = analyzeClosureCandidates("""
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
        #expect(analyzeClosureCandidates("""
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
        #expect(analyzeClosureCandidates("func names() { let names = items.map { $0.name } }").isEmpty)
    }

    @Test("a closure not passed to a collection operation is ignored")
    func nonCollectionClosureIsIgnored() {
        // `Task { }` takes a closure too. A closure run for its effects is not a property waiting
        // to be named, and the operation list is a fixed one for exactly that reason.
        #expect(analyzeClosureCandidates("""
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
        #expect(analyzeClosureCandidates("""
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
        let issues = analyzeClosureCandidates("""
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
        let issues = analyzeClosureCandidates("""
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
        let issues = analyzeClosureCandidates("""
        struct Model {
            var filteredFiles: [File] {
                files.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
            }
        }
        """)

        #expect(issues.first?.symbol == "filteredFiles")
    }

    // MARK: - The loop must converge (B11)

    /// **A rule that cannot recognise its own advice being taken never terminates.**
    ///
    /// The rule tells a reader to lift a closure's logic into a named function. The call site they
    /// are left with is *itself a closure* — a forwarding one — and the rule reported it again,
    /// saying "extract it into a named value type" about a closure whose entire body is a call to the
    /// type they created one step earlier. All three cold readers hit this; one walked the loop three
    /// times before stopping.
    @Test("a closure forwarding to an already-extracted function is NOT reported")
    func forwardingClosureIsNotReported() {
        #expect(analyzeClosureCandidates("""
        struct Model {
            func filtered() -> [File] {
                files.filter { search.matches(name: $0.name) }
            }
        }
        """, projectFunctions: ["matches(name:)"]).isEmpty)
    }

    /// The discrimination this rule turns on. These two closures are **the same shape** — one call,
    /// plain operands — and only ownership separates them. `localizedCaseInsensitiveContains` is
    /// Foundation's: it cannot be seeded, so the law must be stated at the closure or nowhere, and
    /// every locale bug that hides in one is why the rule fires on call-shaped predicates at all.
    @Test("a closure calling a function we did NOT declare still fires")
    func closureCallingForeignFunctionStillFires() {
        #expect(analyzeClosureCandidates("""
        struct Model {
            func filtered() -> [File] {
                files.filter { $0.name.localizedCaseInsensitiveContains(query) }
            }
        }
        """, projectFunctions: ["matches(name:)"]).isEmpty == false)
    }

    /// The instant the closure does work of its own around the call, it is expressing a rule again.
    @Test("forwarding plus logic of its own still fires")
    func forwardingPlusLogicStillFires() {
        #expect(analyzeClosureCandidates("""
        struct Model {
            func filtered() -> [File] {
                files.filter { search.matches(name: $0.name) && !$0.isHidden }
            }
        }
        """, projectFunctions: ["matches(name:)"]).isEmpty == false)
    }

    /// After extracting a comparator, the adapter is all that is left. Refusing to see it as plumbing
    /// never converges — extracting the projection just yields another nested call, forever.
    @Test("a coherent projection into an extracted comparator is plumbing, not a finding")
    func coherentProjectionIsNotReported() {
        #expect(analyzeClosureCandidates("""
        struct Model {
            func ordered() -> [File] {
                files.sorted { a, b in
                    FileOrdering.precedes(
                        FileSortKey(isFolder: a.isFolder, name: a.name),
                        FileSortKey(isFolder: b.isFolder, name: b.name)
                    )
                }
            }
        }
        """, projectFunctions: ["precedes(_:_:)"]).isEmpty)
    }

    /// **The bug that slipped past the first cut.** Each projection draws from a single base, so each
    /// is individually "coherent" — and the comparator ignores its left operand entirely. No law on
    /// `precedes` can see this: the law is checked against *generated* keys and never runs the
    /// adapter. Exempting it would silence the only rule that could have spoken.
    @Test("a projection that never uses one of the closure's parameters still fires")
    func projectionIgnoringAParameterStillFires() {
        #expect(analyzeClosureCandidates("""
        struct Model {
            func ordered() -> [File] {
                files.sorted { a, b in
                    FileOrdering.precedes(
                        FileSortKey(isFolder: b.isFolder, name: b.name),
                        FileSortKey(isFolder: b.isFolder, name: b.name)
                    )
                }
            }
        }
        """, projectFunctions: ["precedes(_:_:)"]).isEmpty == false)
    }

    /// A projection that *combines* two values is a decision, not an adapter.
    @Test("a projection mixing two parameters in one key still fires")
    func projectionMixingParametersStillFires() {
        #expect(analyzeClosureCandidates("""
        struct Model {
            func ordered() -> [File] {
                files.sorted { a, b in
                    FileOrdering.precedes(
                        FileSortKey(isFolder: a.isFolder, name: b.name),
                        FileSortKey(isFolder: b.isFolder, name: b.name)
                    )
                }
            }
        }
        """, projectFunctions: ["precedes(_:_:)"]).isEmpty == false)
    }
}
