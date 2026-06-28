import Foundation
import SwiftProjectLintModels
import SwiftProjectLintRegistry
import SwiftProjectLintVisitors

/// Registrar for the Missing Equatable on State Type rule.
///
/// A cross-file rule: flags a project value type used in SwiftUI state
/// (`@State` / `@Binding` / `@Published`) that conforms to neither `Equatable`
/// nor `Hashable` anywhere in the project — the conformance that would make its
/// state a property-test subject.
struct MissingEquatableOnStateType: PatternRegistrarProtocol {

    var pattern: SyntaxPattern {
        SyntaxPattern(
            name: .missingEquatableOnStateType,
            visitor: MissingEquatableOnStateTypeVisitor.self,
            severity: .info,
            category: .testability,
            messageTemplate: "Value type held in SwiftUI state conforms to neither Equatable "
                + "nor Hashable, so it can't be a property-test subject.",
            suggestion: "Add `Equatable` (or `Hashable`) so the state can be asserted on and "
                + "shrunk by property-based tests.",
            description: "Detects value types used in @State / @Binding / @Published that lack "
                + "an Equatable/Hashable conformance anywhere in the project."
        )
    }
}
