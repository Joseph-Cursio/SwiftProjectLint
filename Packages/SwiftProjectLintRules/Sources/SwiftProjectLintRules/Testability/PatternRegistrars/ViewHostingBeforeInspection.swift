import SwiftProjectLintModels
import SwiftProjectLintRegistry
import SwiftProjectLintVisitors

/// Registrar for the ViewHosting Before Inspection rule.
///
/// Flags a ViewInspector test that hosts a view and only then inspects it. Hosting drives the
/// inspection, so the callback has to be registered first; inspecting afterwards evaluates the
/// body out of the tree, which traps for a view reading `@Environment(SomeType.self)`.
struct ViewHostingBeforeInspection: PatternRegistrarProtocol {

    var pattern: SyntaxPattern {
        SyntaxPattern(
            name: .viewHostingBeforeInspection,
            visitor: ViewHostingBeforeInspectionVisitor.self,
            severity: .error,
            category: .testability,
            messageTemplate: "ViewHosting.host(…) runs before the view is inspected — the "
                + "inspection must be registered first, and hosting drives it",
            suggestion: "Either register the callback before hosting "
                + "(`let exp = sut.inspection.inspect { … }` then `ViewHosting.host(…)`), or "
                + "nest it inside `try await ViewHosting.host(sut) { … }`.",
            description: "Inspecting after hosting still evaluates the body out-of-tree. For a "
                + "view reading @Environment(SomeType.self) that traps rather than fails, "
                + "killing the test process and reporting every co-scheduled test as failed at "
                + "0.000s — a different set each run, with a backtrace naming neither "
                + "ViewInspector nor the offending test. Measured on macOS 27."
        )
    }
}
