/// What a seeded symbol still needs before a law over it compiles — and nothing else is wrong.
///
/// ## Why the manifest needs this
///
/// A pure function whose result a test cannot compare with `==` was dropped from the manifest
/// without a word: `PropertyTestCandidacy` gates on an assertable result, and a type that is not
/// `Equatable` fails the gate. That is the right gate and the wrong silence when the only thing
/// missing is a conformance the compiler would synthesize. SwiftLintRuleStudio's
/// `MigrationAssistant.detectMigrations` is the case that showed it: pure, total, and invisible to
/// the pipeline, because `MigrationPlan` and the `MigrationStep` it holds were never declared
/// `Equatable`. A mutation run then found eight surviving mutants in that one file, and no tool
/// downstream had been told the function existed.
///
/// So the seed is emitted, and the conformance it is waiting on travels with it. The finding a
/// person reads says the same thing in prose (`missingEquatableOnPureResult`); this is the form a
/// consumer can act on — name the types in the stub it writes, or hold the law back until they
/// conform.
///
/// ## What it promises
///
/// Every type named here is declared in the scanned project, is a `struct` or `enum`, and would get
/// a **synthesized** `Equatable` from a bare `: Equatable` — every stored property or associated
/// value is already `Equatable`, or is another type on this list. A type that would need a
/// hand-written `==` (a stored closure, an existential, a tuple, a class that is not `Equatable`) is
/// never named, and the seed is not emitted at all: the remedy has to be one keyword per type, or
/// it is not a remedy the linter can state.
///
/// ## Deliberately not a version bump
///
/// The manifest stays at version 2, on the same terms as `role`. A consumer that ignores this field
/// loses the remedy and misreads nothing: it sees an ordinary `pure-function` seed whose result is
/// not `Equatable`, which `swift-infer` already caveats in its own words ("the return type must be
/// Equatable for the law to compile").
public struct PBTSeedRequirement: Codable, Sendable, Equatable {

    /// The project types that need `Equatable` declared, the result's own type first and the rest
    /// in name order. Never empty: an issue with nothing required carries no requirement at all.
    public let equatable: [String]

    public init(equatable: [String]) {
        self.equatable = equatable
    }
}
