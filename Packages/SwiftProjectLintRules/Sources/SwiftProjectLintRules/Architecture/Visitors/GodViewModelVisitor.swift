import SwiftProjectLintModels
import SwiftProjectLintRegistry
import SwiftProjectLintVisitors
import SwiftSyntax

/// Detects view models with too many published properties (god objects).
///
/// View models with many `@Published` properties manage too much state, are
/// hard to test, and couple unrelated concerns. For `@Observable` classes, all
/// `var` properties are implicitly observed so a higher threshold is used.
final class GodViewModelVisitor: BasePatternVisitor {
    private var currentFilePath: String = ""

    /// Threshold for `@Published` property count in `ObservableObject` classes.
    private static let publishedThreshold = 10

    /// Threshold for `var` property count in `@Observable` classes.
    private static let observableThreshold = 15

    required init(pattern: SyntaxPattern, viewMode: SyntaxTreeViewMode = .sourceAccurate) {
        super.init(pattern: pattern, viewMode: viewMode)
    }

    override func setFilePath(_ filePath: String) {
        self.currentFilePath = filePath
    }

    override func visit(_ node: ClassDeclSyntax) -> SyntaxVisitorContinueKind {
        let className = node.name.text

        if conformsToObservableObject(node.inheritanceClause) {
            let publishedCount = countPublishedProperties(node.memberBlock)
            if publishedCount > Self.publishedThreshold {
                reportGodViewModel(
                    className: className,
                    count: publishedCount,
                    kind: "@Published",
                    node: node
                )
            }
        } else if hasObservableAttribute(node.attributes) {
            let varCount = countVarProperties(node.memberBlock)
            if varCount > Self.observableThreshold {
                reportGodViewModel(
                    className: className,
                    count: varCount,
                    kind: "observed",
                    node: node
                )
            }
        }

        return .visitChildren
    }

    // MARK: - Helpers

    private func conformsToObservableObject(
        _ clause: InheritanceClauseSyntax?
    ) -> Bool {
        guard let clause else { return false }
        return clause.inheritedTypes.contains { inherited in
            inherited.type.trimmedDescription == "ObservableObject"
        }
    }

    private func hasObservableAttribute(_ attributes: AttributeListSyntax) -> Bool {
        attributes.contains { attr in
            guard let attrSyntax = attr.as(AttributeSyntax.self) else { return false }
            return attrSyntax.attributeName.trimmedDescription == "Observable"
        }
    }

    private func countPublishedProperties(_ memberBlock: MemberBlockSyntax) -> Int {
        var count = 0
        for member in memberBlock.members {
            guard let varDecl = member.decl.as(VariableDeclSyntax.self) else { continue }
            let hasPublished = varDecl.attributes.contains { attr in
                guard let attrSyntax = attr.as(AttributeSyntax.self) else { return false }
                return attrSyntax.attributeName.trimmedDescription == "Published"
            }
            if hasPublished {
                count += varDecl.bindings.count
            }
        }
        return count
    }

    private func countVarProperties(_ memberBlock: MemberBlockSyntax) -> Int {
        var count = 0
        for member in memberBlock.members {
            guard let varDecl = member.decl.as(VariableDeclSyntax.self),
                  varDecl.bindingSpecifier.text == "var" else { continue }
            // Skip computed properties (have accessor blocks)
            for binding in varDecl.bindings where binding.accessorBlock == nil {
                count += 1
            }
        }
        return count
    }

    private func reportGodViewModel(
        className: String,
        count: Int,
        kind: String,
        node: ClassDeclSyntax
    ) {
        addIssue(
            severity: .warning,
            message: "'\(className)' has \(count) \(kind) properties "
                + "— consider splitting into focused view models",
            filePath: currentFilePath,
            lineNumber: getLineNumber(for: Syntax(node)),
            suggestion: "Group related properties into separate "
                + "ObservableObject classes and compose at the view level.",
            ruleName: .godViewModel
        )
    }
}
