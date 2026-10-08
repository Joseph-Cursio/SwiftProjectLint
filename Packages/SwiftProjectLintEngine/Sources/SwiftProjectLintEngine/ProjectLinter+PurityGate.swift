import SwiftProjectLintModels
import SwiftProjectLintRegistry
import SwiftProjectLintVisitors

/// The purity gate: what a run builds of the package purity, derived from what the visitors it
/// will execute declare (`PackagePurityConsumer`), and the fallback that keeps a missing
/// declaration from costing a finding.
extension ProjectLinter {

    /// What one run builds of the package purity.
    ///
    /// The construction universe — the nested-off walk, the manifest reads, the universe-only parses
    /// and `PackagePurity.build` — is built when any input is, because both pre-scan catalogs are
    /// resolved with the oracle too. Each catalog is built only when some visitor declares it.
    struct PurityDemand: Equatable, Sendable {
        let inputs: PackagePurityInputs

        /// What a run built before the gate existed, and what the fallback rerun builds.
        static let everything = Self(inputs: .all)

        init(inputs: PackagePurityInputs) {
            self.inputs = inputs
        }

        /// The union of the declarations of every visitor `planned` will execute.
        ///
        /// Taken over **patterns**, each carrying its visitor's declaration, so a visitor shared by
        /// several rules counts whenever any of them is planned — which is exactly when the
        /// per-file detector (one walk per visitor type among the requested patterns) and the
        /// cross-file engine (one visitor per requested pattern) run it. `nil` is every registered
        /// pattern, as it is to both.
        init(planned: [RuleIdentifier]?, registry: PatternVisitorRegistry) {
            let patterns = registry.getAllPatterns()
            let running = planned.map { names in
                let names = Set(names)
                return patterns.filter { names.contains($0.name) }
            } ?? patterns
            self.inputs = running.reduce(into: []) { $0.formUnion($1.packagePurityInputs) }
        }

        var buildsTable: Bool { !inputs.isEmpty }

        func builds(_ input: PackagePurityInputs) -> Bool { inputs.isSuperset(of: input) }
    }

    /// One run's findings and what its purity gate did.
    struct LintRun {
        let issues: [LintIssue]
        /// The demand derived from the declarations — not the `.everything` a rerun forced.
        let demand: PurityDemand
        /// Reads of what the run withheld. Non-empty means a visitor read package purity without
        /// declaring it, the first pass's findings were discarded, and `issues` is the rerun's.
        let trips: [PurityTripwire.Trip]
    }

    static func undeclaredReadMessage(_ trips: [PurityTripwire.Trip]) -> String {
        "a visitor read package purity it does not declare (PackagePurityConsumer) — the run was "
            + "redone with everything built; PurityGateDeclarationTests names the rule. Reads: "
            + trips.map(\.description).joined(separator: "; ")
    }
}
