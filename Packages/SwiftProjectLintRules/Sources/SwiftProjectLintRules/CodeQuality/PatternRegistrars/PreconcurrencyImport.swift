import Foundation
import SwiftProjectLintModels
import SwiftProjectLintRegistry
import SwiftProjectLintVisitors

/// A registrar for the `@preconcurrency import` pattern.
///
/// Flags imports that relax concurrency checking for an entire module — the
/// blanket escape hatch the `Preconcurrency Conformance` rule intentionally skips.
struct PreconcurrencyImport: PatternRegistrarProtocol {

    var pattern: SyntaxPattern {
        SyntaxPattern(
            name: .preconcurrencyImport,
            visitor: PreconcurrencyImportVisitor.self,
            severity: .info,
            category: .codeQuality,
            messageTemplate: "@preconcurrency import relaxes concurrency checking "
                + "for every type from that module",
            suggestion: "Keep the suppression only while the module lacks its own concurrency "
                + "annotations; remove @preconcurrency once it adopts Sendable / isolation.",
            description: "Detects @preconcurrency on import declarations. The annotation "
                + "softens concurrency diagnostics for the whole module — a legitimate but "
                + "blanket escape hatch worth auditing."
        )
    }
}
