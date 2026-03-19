import Foundation
import SwiftParser
import SwiftSyntax

//
//  ViewRelationshipVisitor.swift
//  SwiftProjectLint
//
//  Created by Joseph Cursio on 7/3/25.
//

/// A SwiftSyntax visitor that extracts view relationships from Swift source code.
/// 
/// This visitor analyzes SwiftUI view hierarchies to detect various types of
/// relationships including direct child views, navigation destinations, modal
/// presentations, and more. It supports the following relationship types:
/// - Direct child views (e.g., `RoundView()`)
/// - Navigation destinations (e.g., `NavigationLink(destination: DetailView())`)
/// - Modal presentations (sheet, fullScreenCover, popover)
/// - Alert presentations
/// - Tab view selections
class ViewRelationshipVisitor: SyntaxVisitor {
    var relationships: [ViewRelationship] = []
    private let parentView: String
    private let filePath: String
    private let sourceContents: String
    private let sourceLocationConverter: SourceLocationConverter
    private var detectedSpecialViews: Set<String> = []
    private let containerViews: Set<String> = Set(SwiftUIViewType.containerViews.map(\.rawValue))
    private let systemViews: Set<String> = Set(SwiftUIViewType.systemViews.map(\.rawValue))

    // Track context to avoid detecting views in wrong contexts
    private var isInContainer = false
    private var isInPresentationModifier = false
    private var isInNavigationLink = false

    // Cache for line number calculations to improve performance
    private var lineNumberCache: [AbsolutePosition: Int] = [:]

    init(
        parentView: String,
        filePath: String,
        sourceContents: String,
        sourceLocationConverter: SourceLocationConverter
    ) {
        self.parentView = parentView
        self.filePath = filePath
        self.sourceContents = sourceContents
        self.sourceLocationConverter = sourceLocationConverter
        super.init(viewMode: .sourceAccurate)
    }

    override func visit(_ node: FunctionCallExprSyntax) -> SyntaxVisitorContinueKind {
        // Handle NavigationLink
        if let called = node.calledExpression.as(DeclReferenceExprSyntax.self),
           called.baseName.text == "NavigationLink" {
            let wasInNavigationLink = isInNavigationLink
            isInNavigationLink = true

            if let destArg = node.arguments.first(where: { $0.label?.text == "destination" }),
               let destCall = destArg.expression.as(FunctionCallExprSyntax.self) {
                if let destName = extractViewName(from: destCall) {
                    addRelationship(
                        childView: destName,
                        relationshipType: .navigationDestination,
                        node: Syntax(node)
                    )
                    detectedSpecialViews.insert(destName)
                }
            }

            // Visit children to handle the content closure
            let result = super.visit(node)
            isInNavigationLink = wasInNavigationLink
            return result
        }

        // Handle container views - just visit children normally
        if let called = node.calledExpression.as(DeclReferenceExprSyntax.self),
           containerViews.contains(called.baseName.text) {
            // Set flag to indicate we're inside a container
            let wasInContainer = isInContainer
            isInContainer = true

            // Visit children normally - they will be detected as direct children
            let result = super.visit(node)
            isInContainer = wasInContainer
            return result
        }

        // Handle presentation modifiers
        if let memberAccess = node.calledExpression.as(MemberAccessExprSyntax.self) {
            let modifier = memberAccess.declName.baseName.text
            if let relType = relationshipType(for: modifier) {
                let wasInPresentationModifier = isInPresentationModifier
                isInPresentationModifier = true

                // Labeled closure argument (e.g., content: { ... })
                if let contentArg = node.arguments.first(where: { $0.label?.text == "content" }) {
                    extractViewFromClosure(contentArg.expression, relationshipType: relType, node: Syntax(node))
                }
                // Trailing closure
                else if let trailing = node.trailingClosure {
                    extractViewFromClosure(ExprSyntax(trailing), relationshipType: relType, node: Syntax(node))
                }

                let result = super.visit(node)
                isInPresentationModifier = wasInPresentationModifier
                return result
            }
        }

        // Handle direct child instantiation (only if not in special contexts)
        if let called = node.calledExpression.as(DeclReferenceExprSyntax.self) {
            let viewName = called.baseName.text
            if !containerViews.contains(viewName) &&
               !systemViews.contains(viewName) &&
               !detectedSpecialViews.contains(viewName) &&
               !isInPresentationModifier &&
               !isInNavigationLink {
                addRelationship(
                    childView: viewName,
                    relationshipType: .directChild,
                    node: Syntax(node)
                )
            }
        }
        return .visitChildren
    }

    override func visit(_ node: StructDeclSyntax) -> SyntaxVisitorContinueKind {
        return .visitChildren
    }

    // MARK: - Helpers

    private func extractViewFromClosure(
        _ expr: ExprSyntax,
        relationshipType: RelationshipType,
        node: Syntax
    ) {
        if let closure = expr.as(ClosureExprSyntax.self) {
            // Find all custom views in the closure, not just the first one
            let customViews = findAllCustomViews(in: closure.statements)
            for customView in customViews {
                addRelationship(
                    childView: customView,
                    relationshipType: relationshipType,
                    node: node
                )
                detectedSpecialViews.insert(customView)
            }
        }
    }

    // Find all custom view names recursively in a list of statements
    private func findAllCustomViews(in statements: CodeBlockItemListSyntax) -> [String] {
        var customViews: [String] = []
        for statement in statements {
            let views = findAllCustomViews(in: Syntax(statement.item))
            customViews.append(contentsOf: views)
        }
        return customViews
    }

    // Recursively find all custom view names in a syntax node
    private func findAllCustomViews(in expr: Syntax) -> [String] {
        if let call = expr.as(FunctionCallExprSyntax.self) {
            return findCustomViewsInCall(call)
        } else if let codeBlock = expr.as(CodeBlockSyntax.self) {
            return findAllCustomViews(in: codeBlock.statements)
        } else if let sequence = expr.as(SequenceExprSyntax.self) {
            return sequence.elements.flatMap { findAllCustomViews(in: Syntax($0)) }
        } else if let tuple = expr.as(TupleExprSyntax.self) {
            return tuple.elements.flatMap { findAllCustomViews(in: Syntax($0.expression)) }
        }
        return []
    }

    private func findCustomViewsInCall(_ call: FunctionCallExprSyntax) -> [String] {
        let viewName = extractViewNameFromCalledExpression(call.calledExpression)
        guard let name = viewName else { return [] }

        if !containerViews.contains(name) && !systemViews.contains(name) {
            return [name]
        } else if containerViews.contains(name) {
            return findCustomViewsInContainerArgs(call)
        }
        return []
    }

    private func extractViewNameFromCalledExpression(_ expr: ExprSyntax) -> String? {
        if let called = expr.as(DeclReferenceExprSyntax.self) {
            return called.baseName.text
        } else if let member = expr.as(MemberAccessExprSyntax.self) {
            return member.declName.baseName.text
        }
        return nil
    }

    private func findCustomViewsInContainerArgs(_ call: FunctionCallExprSyntax) -> [String] {
        var customViews: [String] = []
        for arg in call.arguments {
            customViews.append(contentsOf: findAllCustomViews(in: Syntax(arg.expression)))
        }
        if let trailing = call.trailingClosure {
            customViews.append(contentsOf: findAllCustomViews(in: trailing.statements))
        }
        return customViews
    }

    private func extractViewName(from call: FunctionCallExprSyntax) -> String? {
        if let id = call.calledExpression.as(DeclReferenceExprSyntax.self) {
            return id.baseName.text
        }
        if let member = call.calledExpression.as(MemberAccessExprSyntax.self) {
            return member.declName.baseName.text
        }
        return nil
    }

    private func addRelationship(
        childView: String,
        relationshipType: RelationshipType,
        node: Syntax
    ) {
        let lineNumber = getLineNumber(for: node)
        let relationship = ViewRelationship(
            parentView: parentView,
            childView: childView,
            relationshipType: relationshipType,
            lineNumber: lineNumber,
            filePath: filePath
        )
        relationships.append(relationship)
    }

    private func getLineNumber(for node: Syntax) -> Int {
        let pos = node.positionAfterSkippingLeadingTrivia
        let loc = sourceLocationConverter.location(for: pos)
        return loc.line
    }

    private func relationshipType(for modifier: String) -> RelationshipType? {
        switch modifier {
        case "sheet":
            return .sheet
        case "popover":
            return .popover
        case "alert":
            return .alert
        case "fullScreenCover":
            return .fullScreenCover
        default:
            return nil
        }
    }

    /// Calculates line number for a given position with caching for performance
    private func calculateLineNumber(for position: AbsolutePosition) -> Int {
        if let cached = lineNumberCache[position] {
            return cached
        }

        let offset = position.utf8Offset
        let prefix = String(sourceContents.prefix(offset))
        let lineNumber = prefix.components(separatedBy: .newlines).count
        lineNumberCache[position] = lineNumber
        return lineNumber
    }
}
