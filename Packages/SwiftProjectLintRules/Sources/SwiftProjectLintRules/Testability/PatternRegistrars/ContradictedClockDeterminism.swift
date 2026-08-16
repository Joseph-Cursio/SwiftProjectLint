import Foundation
import SwiftProjectLintModels
import SwiftProjectLintRegistry
import SwiftProjectLintVisitors

/// Registrar for the Contradicted Clock Determinism rule.
///
/// `severity: .warning` rather than `.info`, which the neighbouring testability
/// rules mostly use, because this is the only one in the family reporting a
/// statement the author made and the code refutes. The others describe a shape
/// that *could* be more testable; this one says two parts of the same file
/// disagree, and a downstream tool is trusting the wrong half.
struct ContradictedClockDeterminism: PatternRegistrarProtocol {

    var pattern: SyntaxPattern {
        SyntaxPattern(
            name: .contradictedClockDeterminism,
            visitor: ContradictedClockDeterminismVisitor.self,
            severity: .warning,
            category: .testability,
            messageTemplate: "Annotated clock-deterministic, but the body reads a clock nobody "
                + "passed in",
            suggestion: "Take the clock as a parameter and read it there, or drop the annotation.",
            description: "Reports a function claiming `@ClockDeterministic` (or "
                + "`/// @lint.determinism clock_deterministic`) whose body constructs or reads an "
                + "ambient clock — `Date()`, `ContinuousClock()`, `Task.sleep(for:)`. The claim "
                + "exists so a consumer can relax its async veto, so an unchecked one admits a "
                + "time-dependent function to property-based verification, where it flakes."
        )
    }
}
