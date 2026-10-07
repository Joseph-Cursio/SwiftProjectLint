import SwiftProjectLintModels
import SwiftProjectLintRegistry
import SwiftProjectLintVisitors

/// Registrar for the Observable Environment View Missing Inspection Hook rule.
///
/// Flags a view that reads `@Environment(SomeType.self)` but carries no inspection relay, so
/// ViewInspector cannot evaluate its body without trapping. Advisory: a view nobody inspects
/// needs no hook.
struct ObservableEnvironmentViewMissingInspectionHook: PatternRegistrarProtocol {

    var pattern: SyntaxPattern {
        SyntaxPattern(
            name: .observableEnvViewMissingInspectionHook,
            visitor: ObservableEnvironmentViewMissingInspectionHookVisitor.self,
            severity: .info,
            category: .testability,
            messageTemplate: "View reads @Environment(SomeType.self) but has no inspection "
                + "relay — ViewInspector cannot evaluate its body without trapping",
            suggestion: "If the view is inspected in tests, add `internal let inspection = "
                + "Inspection<Self>()` plus `.onReceive(inspection.notice) { … }` to its body.",
            description: "The @Observable form of @Environment has no default value, so reading "
                + "it outside a hosted hierarchy traps. Only the keypath form degrades safely. "
                + "Advisory: a view nobody inspects needs no hook, but adding it up front beats "
                + "discovering the constraint via a process-killing trap."
        )
    }
}
