import Foundation
import SwiftProjectLintModels
import SwiftProjectLintRegistry
import SwiftProjectLintVisitors

/// A registrar for the swallowed-injection-downcast pattern.
///
/// Flags initializers that accept a protocol-typed dependency and then downcast it to a
/// concrete type, defeating the dependency-injection seam they appear to offer.
struct SwallowedInjectionDowncast: PatternRegistrarProtocol {

    var pattern: SyntaxPattern {
        SyntaxPattern(
            name: .swallowedInjectionDowncast,
            visitor: SwallowedInjectionDowncastVisitor.self,
            severity: .info,
            category: .codeQuality,
            messageTemplate: "Initializer downcasts an injected protocol parameter to a "
                + "concrete type, dropping any other conformer",
            suggestion: "Store the parameter through its protocol type and use the injected "
                + "value directly instead of downcasting it.",
            description: "Detects an initializer that takes a protocol-typed dependency and "
                + "downcasts it (as? / as!) to a concrete type — a dependency-injection seam "
                + "that silently discards substitutes such as test doubles."
        )
    }
}
