import SwiftProjectLintModels
import SwiftProjectLintVisitors
import SwiftSyntax

/// Detects a `View` that reads `@Environment(SomeType.self)` but carries no
/// inspection relay, so ViewInspector cannot evaluate its `body` without
/// trapping.
///
/// The `@Observable` form `@Environment(SomeType.self)` has **no default
/// value**. Read outside a hosted view hierarchy it traps in SwiftUICore's
/// `EnvironmentValues.subscript.getter` — killing the test process rather than
/// failing one test. The keypath form `@Environment(\.someKey)` is fine: it
/// falls back to a default and merely logs a warning.
///
/// The only way to test such a view is to host it and inspect from inside the
/// live render, which requires the view to carry a relay:
///
/// ```swift
/// internal let inspection = Inspection<Self>()
///
/// var body: some View {
///     …
///     .onReceive(inspection.notice) { inspection.visit(self, $0) }
/// }
/// ```
///
/// This is advisory rather than a defect: a view nobody inspects needs no hook.
/// It fires early, at the point the view is written, instead of leaving the
/// discovery to a process-killing trap whose backtrace names neither
/// ViewInspector nor the offending test.
///
/// Companion to ``RuleIdentifier/viewHostingBeforeInspection``, which catches
/// the same hazard from the test side.
final class ObservableEnvironmentViewMissingInspectionHookVisitor: BasePatternVisitor {

    required init(pattern: SyntaxPattern, viewMode: SyntaxTreeViewMode = .sourceAccurate) {
        super.init(pattern: pattern, viewMode: viewMode)
    }

    override func visit(_ node: StructDeclSyntax) -> SyntaxVisitorContinueKind {
        guard Self.conformsToView(node) else { return .visitChildren }

        let observableReads = Self.observableEnvironmentProperties(in: node)
        guard !observableReads.isEmpty else { return .visitChildren }
        guard !Self.hasInspectionHook(node) else { return .visitChildren }

        let names = observableReads.joined(separator: ", ")
        addIssue(
            severity: .info,
            message: "\(node.name.text) reads @Environment(\(names)) but has no inspection relay "
                + "— ViewInspector cannot evaluate this body without trapping",
            filePath: getFilePath(for: Syntax(node)),
            lineNumber: getLineNumber(for: Syntax(node)),
            suggestion: "If this view is inspected in tests, add `internal let inspection = "
                + "Inspection<Self>()` and `.onReceive(inspection.notice) { inspection.visit(self, $0) }` "
                + "to its body, then host it in the test rather than inspecting directly.",
            ruleName: .observableEnvironmentViewMissingInspectionHook
        )
        return .visitChildren
    }

    // MARK: - Detection

    private static func conformsToView(_ node: StructDeclSyntax) -> Bool {
        node.inheritanceClause?.inheritedTypes.contains { inherited in
            inherited.type.as(IdentifierTypeSyntax.self)?.name.text == "View"
        } ?? false
    }

    /// Type names read via the `@Environment(SomeType.self)` form. The keypath
    /// form is deliberately excluded — it has a default and does not trap.
    private static func observableEnvironmentProperties(in node: StructDeclSyntax) -> [String] {
        var found: [String] = []
        for member in node.memberBlock.members {
            guard let variable = member.decl.as(VariableDeclSyntax.self) else { continue }
            for attribute in variable.attributes {
                guard let attr = attribute.as(AttributeSyntax.self),
                      attr.attributeName.as(IdentifierTypeSyntax.self)?.name.text == "Environment",
                      let args = attr.arguments?.as(LabeledExprListSyntax.self),
                      let first = args.first?.expression.as(MemberAccessExprSyntax.self),
                      first.declName.baseName.text == "self",
                      let type = first.base?.as(DeclReferenceExprSyntax.self) else {
                    continue
                }
                found.append("\(type.baseName.text).self")
            }
        }
        return found
    }

    /// Whether the struct declares a stored property named `inspection`.
    private static func hasInspectionHook(_ node: StructDeclSyntax) -> Bool {
        node.memberBlock.members.contains { member in
            guard let variable = member.decl.as(VariableDeclSyntax.self) else { return false }
            return variable.bindings.contains { binding in
                binding.pattern.as(IdentifierPatternSyntax.self)?.identifier.text == "inspection"
            }
        }
    }
}
