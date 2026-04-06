import SwiftProjectLintModels
import SwiftProjectLintRegistry
import SwiftProjectLintVisitors
import SwiftSyntax

/// Detects `@Attribute(.unique)` on stored properties inside `@Model` classes.
///
/// `@Attribute(.unique)` silently breaks CloudKit sync — CloudKit doesn't support
/// uniqueness constraints at the server level, and the combination causes sync
/// conflicts or data loss. Since we cannot reliably detect CloudKit usage from
/// source alone, this rule flags all occurrences at `.warning` severity.
final class SwiftDataUniqueAttributeCloudKitVisitor: BasePatternVisitor {
    private var currentFilePath: String = ""
    private var insideModelClass = false

    required init(pattern: SyntaxPattern, viewMode: SyntaxTreeViewMode = .sourceAccurate) {
        super.init(pattern: pattern, viewMode: viewMode)
    }

    override func setFilePath(_ filePath: String) {
        self.currentFilePath = filePath
    }

    // MARK: - Track @Model classes

    override func visit(_ node: ClassDeclSyntax) -> SyntaxVisitorContinueKind {
        if hasModelAttribute(node.attributes) {
            insideModelClass = true
        }
        return .visitChildren
    }

    override func visitPost(_ node: ClassDeclSyntax) {
        insideModelClass = false
    }

    // MARK: - Detect @Attribute(.unique)

    override func visit(_ node: VariableDeclSyntax) -> SyntaxVisitorContinueKind {
        guard insideModelClass,
              hasUniqueAttribute(node.attributes) else {
            return .visitChildren
        }

        let propertyName = node.bindings.first?
            .pattern.as(IdentifierPatternSyntax.self)?
            .identifier.text ?? "property"

        addIssue(
            severity: .warning,
            message: "@Attribute(.unique) on '\(propertyName)' may break CloudKit sync "
                + "— CloudKit does not support uniqueness constraints",
            filePath: currentFilePath,
            lineNumber: getLineNumber(for: Syntax(node)),
            suggestion: "Remove @Attribute(.unique) if this model syncs via CloudKit. "
                + "If not using CloudKit, suppress with "
                + "// swiftprojectlint:disable swiftdata-unique-attribute-cloudkit",
            ruleName: .swiftDataUniqueAttributeCloudKit
        )
        return .visitChildren
    }

    // MARK: - Helpers

    private func hasModelAttribute(_ attributes: AttributeListSyntax) -> Bool {
        attributes.contains { attr in
            guard let attrSyntax = attr.as(AttributeSyntax.self) else { return false }
            return attrSyntax.attributeName.trimmedDescription == "Model"
        }
    }

    private func hasUniqueAttribute(_ attributes: AttributeListSyntax) -> Bool {
        attributes.contains { attr in
            guard let attrSyntax = attr.as(AttributeSyntax.self),
                  attrSyntax.attributeName.trimmedDescription == "Attribute",
                  let args = attrSyntax.arguments?.as(LabeledExprListSyntax.self) else {
                return false
            }
            return args.contains { arg in
                arg.expression.trimmedDescription.contains(".unique")
            }
        }
    }
}
