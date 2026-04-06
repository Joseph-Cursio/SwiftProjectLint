import SwiftProjectLintModels
import SwiftProjectLintRegistry
import SwiftProjectLintVisitors
import Foundation
import SwiftSyntax

/// Detects computed properties that return `some View` inside View-conforming types.
///
/// Computed properties returning `some View` defeat SwiftUI's structural identity — they are
/// re-evaluated on every parent update with no diffing. Extracting them into separate `View`
/// structs gives SwiftUI a stable identity boundary and lets the child hold its own `@State`.
class ComputedPropertyViewVisitor: BasePatternVisitor {
    private var currentFilePath: String = ""
    private var isInsideViewType = false

    required init(pattern: SyntaxPattern, viewMode: SyntaxTreeViewMode = .sourceAccurate) {
        super.init(pattern: pattern, viewMode: viewMode)
    }

    override func setFilePath(_ filePath: String) {
        self.currentFilePath = filePath
    }

    // MARK: - Track View-conforming types

    override func visit(_ node: StructDeclSyntax) -> SyntaxVisitorContinueKind {
        if conformsToView(node.inheritanceClause) || hasBodySomeView(node.memberBlock) {
            isInsideViewType = true
        }
        return .visitChildren
    }

    override func visitPost(_ node: StructDeclSyntax) {
        isInsideViewType = false
    }

    override func visit(_ node: ClassDeclSyntax) -> SyntaxVisitorContinueKind {
        if conformsToView(node.inheritanceClause) || hasBodySomeView(node.memberBlock) {
            isInsideViewType = true
        }
        return .visitChildren
    }

    override func visitPost(_ node: ClassDeclSyntax) {
        isInsideViewType = false
    }

    // MARK: - Detect computed properties returning some View

    override func visit(_ node: VariableDeclSyntax) -> SyntaxVisitorContinueKind {
        guard isInsideViewType else { return .visitChildren }

        for binding in node.bindings {
            guard let name = binding.pattern.as(IdentifierPatternSyntax.self)?.identifier.text,
                  name != "body",
                  returnsSomeView(binding.typeAnnotation),
                  binding.accessorBlock != nil else {
                continue
            }

            let hasViewBuilder = node.attributes.contains { attr in
                guard let attrSyntax = attr.as(AttributeSyntax.self) else { return false }
                return attrSyntax.attributeName.trimmedDescription == "ViewBuilder"
            }

            let severity: IssueSeverity = hasViewBuilder ? .info : .warning
            let qualifier = hasViewBuilder ? " @ViewBuilder" : ""

            addIssue(
                severity: severity,
                message: "Computed\(qualifier) property '\(name)' returns 'some View' — "
                    + "extract into a separate View struct for better SwiftUI diffing",
                filePath: currentFilePath,
                lineNumber: getLineNumber(for: Syntax(node)),
                suggestion: "Move '\(name)' into its own struct conforming to View",
                ruleName: .computedPropertyView
            )
        }
        return .skipChildren
    }

    // MARK: - Helpers

    private func conformsToView(_ clause: InheritanceClauseSyntax?) -> Bool {
        guard let clause else { return false }
        return clause.inheritedTypes.contains { inherited in
            inherited.type.trimmedDescription == "View"
        }
    }

    private func hasBodySomeView(_ memberBlock: MemberBlockSyntax) -> Bool {
        for member in memberBlock.members {
            guard let varDecl = member.decl.as(VariableDeclSyntax.self) else { continue }
            for binding in varDecl.bindings {
                guard let name = binding.pattern.as(IdentifierPatternSyntax.self)?.identifier.text,
                      name == "body",
                      returnsSomeView(binding.typeAnnotation) else {
                    continue
                }
                return true
            }
        }
        return false
    }

    private func returnsSomeView(_ annotation: TypeAnnotationSyntax?) -> Bool {
        guard let annotation else { return false }
        guard let someType = annotation.type.as(SomeOrAnyTypeSyntax.self) else { return false }
        return someType.constraint.trimmedDescription == "View"
    }
}
