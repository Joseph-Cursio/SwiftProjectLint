@testable import Core
import SwiftParser
@testable import SwiftProjectLintRules
@testable import SwiftProjectLintVisitors
import SwiftSyntax
import Testing

/// The forwarding gate keys a callee by name, and a name has to be specific enough to key on.
///
/// Split from `PureClosureCandidateVisitorTests` because it is about `ForwardingCall` rather than
/// about the census, and because adding it there took that type past the body-length limit.
@Suite("The forwarding key must name something specific")
struct ForwardingCallKeyTests {

    /// **A project method named `contains(_:)` must not silence every `.contains(…)` in the
    /// package.** One such method removed 49 closure candidates from this repository's census,
    /// silently, and a falling number was the only symptom.
    ///
    /// `set.contains(x)` and `myCatalog.contains(x)` are the same key to a per-file visitor with no
    /// type information, so an unlabelled member call on a lowercase base is no longer keyed on.
    @Test("an unlabelled member call on a value base is not treated as a forward")
    func unlabelledMemberCallOnAValueIsNotAForward() {
        #expect(!analyzeClosureCandidates("""
        struct Model {
            func filtered() -> [String] {
                names.filter { stylingModifierNames.contains($0) }
            }
        }
        """, projectFunctions: ["contains(_:)"]).isEmpty)
    }

    /// The same for the other standard-library names a project might happen to declare.
    ///
    /// Every case is a **predicate** call site on purpose: a single-expression `map` closure is
    /// never a candidate anyway (`hidesALawWorthStating` requires two statements for a transform),
    /// so a `map`-shaped case would have passed while checking nothing — which is how the first
    /// draft of this test failed.
    @Test("common standard-library member names do not exempt a closure", arguments: [
        ("map(_:)", "values.filter { transformer.map($0) }"),
        ("first(_:)", "values.filter { registry.first($0) }"),
        ("hasPrefix(_:)", "values.filter { matcher.hasPrefix($0) }")
    ])
    func standardLibraryNamesDoNotExempt(declared: String, body: String) {
        #expect(!analyzeClosureCandidates("""
        struct Model {
            func run() -> [String] {
                \(body)
            }
        }
        """, projectFunctions: [declared]).isEmpty)
    }

    /// **What the narrowing must not lose.** A labelled member call is a far narrower coincidence
    /// than a bare one, and this is the rule's own motivating example — the convergence case three
    /// cold readers walked in a loop.
    @Test("a labelled member call is still a forward")
    func labelledMemberCallIsStillAForward() {
        #expect(analyzeClosureCandidates("""
        struct Model {
            func filtered() -> [File] {
                files.filter { search.matches(name: $0.name) }
            }
        }
        """, projectFunctions: ["matches(name:)"]).isEmpty)
    }

    /// A capitalized base is a type, not a value that happens to share a name with `Set`.
    @Test("a static call on a project type is still a forward")
    func staticCallOnATypeIsStillAForward() {
        #expect(analyzeClosureCandidates("""
        struct Model {
            func ordered() -> [File] {
                files.filter { FileRules.admits($0) }
            }
        }
        """, projectFunctions: ["admits(_:)"]).isEmpty)
    }
}
