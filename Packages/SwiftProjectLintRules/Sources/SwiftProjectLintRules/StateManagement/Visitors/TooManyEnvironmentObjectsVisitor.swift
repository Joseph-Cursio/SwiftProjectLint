import SwiftProjectLintModels
import SwiftProjectLintRegistry
import SwiftProjectLintVisitors
import Foundation
import SwiftSyntax

/// Visitor that detects SwiftUI views with too many @EnvironmentObject declarations.
///
/// Having 4 or more @EnvironmentObject properties in a single view suggests
/// the view depends on too many external state sources and should consolidate
/// them into a single app-state container or split the view.
class TooManyEnvironmentObjectsVisitor: BasePatternVisitor {

    private static let threshold = 4
    private var isInView = false
    private var currentViewName = ""
    private var environmentObjectCount = 0
    private var viewNode: StructDeclSyntax?

    required init(pattern: SyntaxPattern, viewMode: SyntaxTreeViewMode = .sourceAccurate) {
        super.init(pattern: pattern, viewMode: viewMode)
    }

    override func visit(_ node: StructDeclSyntax) -> SyntaxVisitorContinueKind {
        if isSwiftUIView(node) {
            isInView = true
            currentViewName = node.name.text
            environmentObjectCount = 0
            viewNode = node
        }
        return .visitChildren
    }

    override func visit(_ node: VariableDeclSyntax) -> SyntaxVisitorContinueKind {
        guard isInView else { return .visitChildren }

        if hasEnvironmentObjectWrapper(node) {
            environmentObjectCount += 1
        }
        return .visitChildren
    }

    override func visitPost(_ node: StructDeclSyntax) {
        guard isInView, node.name.text == currentViewName else { return }

        if environmentObjectCount >= Self.threshold, let viewNode {
            addIssue(
                node: Syntax(viewNode),
                variables: [
                    "viewName": currentViewName,
                    "count": "\(environmentObjectCount)"
                ]
            )
        }

        isInView = false
        currentViewName = ""
        environmentObjectCount = 0
        viewNode = nil
    }

    private func hasEnvironmentObjectWrapper(_ node: VariableDeclSyntax) -> Bool {
        for attribute in node.attributes {
            if let attributeSyntax = attribute.as(AttributeSyntax.self),
               let attributeName = attributeSyntax.attributeName.as(IdentifierTypeSyntax.self),
               let wrapper = PropertyWrapper(rawValue: attributeName.name.text),
               wrapper == .environmentObject {
                return true
            }
        }
        return false
    }
}
