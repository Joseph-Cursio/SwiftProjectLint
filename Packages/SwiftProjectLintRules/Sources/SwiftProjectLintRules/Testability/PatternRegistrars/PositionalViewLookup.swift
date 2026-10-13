import SwiftProjectLintModels
import SwiftProjectLintRegistry
import SwiftProjectLintVisitors

/// Registrar for the Positional View Lookup rule.
///
/// Flags a ViewInspector test that reaches a view by its place in the tree — an index, a second
/// step down, a `parent()` — instead of searching for it. The walk restates the layout, so a
/// reorder silently retargets it and a wrapper breaks it.
struct PositionalViewLookup: PatternRegistrarProtocol {

    var pattern: SyntaxPattern {
        SyntaxPattern(
            name: .positionalViewLookup,
            visitor: PositionalViewLookupVisitor.self,
            severity: .warning,
            category: .testability,
            messageTemplate: "A ViewInspector lookup picks a view by its position in the tree",
            suggestion: "Search for the view instead: tag it with `.accessibilityIdentifier(\"…\")` "
                + "and use `find(viewWithAccessibilityIdentifier:)`, or `find(button:)`, "
                + "`find(text:)`, `find(MyRow.self)`.",
            description: "A walk such as `inspect().vStack().hStack(1).button(0)` restates the "
                + "layout: reorder two siblings and it silently reaches the wrong view; wrap or "
                + "extract one, or let the compiler insert a wrapper, and it breaks though nothing "
                + "on screen changed. One step after `inspect()` or `find(…)` is a type assertion "
                + "and is not reported; nor are ForEach row indices or a subject the test file "
                + "declares."
        )
    }
}
