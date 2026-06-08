import Foundation
import SwiftProjectLintModels
import SwiftProjectLintRegistry
import SwiftProjectLintVisitors

/// A registrar for the subclassed-for-mocking pattern.
///
/// Detects a concrete production class that is subclassed by a test double
/// purely to substitute it, where extracting a protocol would let tests use a
/// lightweight conformer instead of subclassing the production type.
struct SubclassedForMocking: PatternRegistrarProtocol {

    var pattern: SyntaxPattern {
        SyntaxPattern(
            name: .subclassedForMocking,
            visitor: SubclassedForMockingVisitor.self,
            severity: .info,
            category: .architecture,
            messageTemplate: "Production class is subclassed by a test double — consider extracting a protocol.",
            suggestion: "Extract a protocol for the substituted surface and inject it, so tests can "
                + "supply a conformer instead of subclassing the production type.",
            description: "Detects a concrete class subclassed by a Mock/Stub/Fake/Spy (or any test-target "
                + "class) with no protocol abstraction, signalling a missed protocol seam."
        )
    }
}
