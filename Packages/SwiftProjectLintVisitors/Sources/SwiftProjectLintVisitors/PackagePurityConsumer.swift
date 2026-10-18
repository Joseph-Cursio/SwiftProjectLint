/// What a visitor reads that the run's package purity decides.
///
/// Three surfaces carry the table into a finding, and nothing else does:
///
/// - ``oracle``: creating a `PurityInferrer`, which takes the run's table at creation — directly,
///   as a stored property, or through a helper that creates one (`PropertyTestCandidacy.candidate`
///   and `shape`, `SelfAccessAnalyzer`). Every query counts, `mutatesCapturedState` included, so
///   no declaration rests on which of SEI's queries happen to read the table today.
/// - ``cleanInstanceMethods``: `knownCleanInstanceMethods`, which the pre-scan resolves with the
///   oracle.
/// - ``impurePackageFunctions``: `knownImpurePackageFunctions`, the one-hop join the pre-scan
///   settles with the oracle.
///
/// The run builds the table when any visitor it will execute declares any of these, and each
/// pre-scan catalog when one declares that catalog. What it does not build it **withholds**: a read
/// of a withheld surface trips the run's ``PurityTripwire`` and the run is redone with everything
/// built, so what a missing declaration leaves unbuilt costs time, never a finding. Where the
/// declaration does decide findings is the reporting scope: see ``PackagePurityConsumer``.
public struct PackagePurityInputs: OptionSet, Sendable, Hashable, CustomStringConvertible {
    public let rawValue: UInt8

    public init(rawValue: UInt8) {
        self.rawValue = rawValue
    }

    public static let oracle = Self(rawValue: 1 << 0)
    public static let cleanInstanceMethods = Self(rawValue: 1 << 1)
    public static let impurePackageFunctions = Self(rawValue: 1 << 2)

    /// Every surface: what a run builds when it cannot tell what its visitors read.
    public static let all: Self = [.oracle, .cleanInstanceMethods, .impurePackageFunctions]

    public var description: String {
        let names: [(Self, String)] = [
            (.oracle, "oracle"),
            (.cleanInstanceMethods, "cleanInstanceMethods"),
            (.impurePackageFunctions, "impurePackageFunctions")
        ]
        return "[" + names.filter { contains($0.0) }.map(\.1).joined(separator: ", ") + "]"
    }
}

/// A visitor whose findings can depend on the package purity, and which of its surfaces it reads.
///
/// **Conforming is the declaration the run's purity gate is derived from.** A visitor type that
/// does not conform declares that it reads none of them, and a run whose visitors all say so
/// neither walks the construction universe nor builds the table or the two pre-scan catalogs.
///
/// **It is also what keeps a rule's findings off the files the table was not built from.** A
/// reported file can be one the construction universe leaves out — under a `tests/` folder, a
/// manifest, a file that is not UTF-8 — and the facts know none of the types it declares, so the run
/// drops every finding of a conforming visitor's rules on such a file (`ProjectLinter.withinPurityScope`).
///
/// The declaration is on the visitor type, not on the rule, because the visitor is what runs: a
/// visitor registered for several rules walks whenever any of them is enabled, and reads whatever
/// it reads whichever of its findings survive the filter. The scope follows it, so every rule of a
/// conforming visitor is kept off those files, including one that reads none of the purity; every
/// conforming visitor reports one rule today, which `everyPurityReadingVisitorReportsOneRule` pins.
///
/// Forgetting it costs at most a second pass in what is built (see ``PackagePurityInputs``), but it is not
/// only slow: the rule then reports on the files the table was not built from, judging them without
/// their own types — the unsound direction. `PurityGateDeclarationTests` runs every rule alone with
/// the table withheld and fails on the first undeclared read, so a new rule that forgets is caught
/// by its first test run.
public protocol PackagePurityConsumer: PatternVisitorProtocol {
    static var packagePurityInputs: PackagePurityInputs { get }
}

extension SyntaxPattern {
    /// What this pattern's visitor declares it reads of the package purity; empty when its visitor
    /// does not conform to ``PackagePurityConsumer``.
    public var packagePurityInputs: PackagePurityInputs {
        (visitor as? any PackagePurityConsumer.Type)?.packagePurityInputs ?? []
    }
}
