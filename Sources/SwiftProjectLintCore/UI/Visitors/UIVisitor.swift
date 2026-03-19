import Foundation
import SwiftSyntax
// import SwiftSyntaxParser
import SwiftParser

/// Visitor for UI patterns (Navigation, preview, styling, ForEach without ID, error handling)
class UIVisitor: BasePatternVisitor {
    private var currentViewName: String = ""
    private var currentFilePath: String = ""
    private var navigationStack: [String] = []
    private var detectedPreviews: Set<String> = []
    private var stylingModifiers: [String: Set<String>] = [:]

    required init(pattern: SyntaxPattern, viewMode: SyntaxTreeViewMode = .sourceAccurate) {
        super.init(pattern: pattern, viewMode: viewMode)
    }

    override func setFilePath(_ filePath: String) {
        self.currentFilePath = filePath
    }

    override func visit(_ node: StructDeclSyntax) -> SyntaxVisitorContinueKind {
        let viewName = node.name.text
        currentViewName = viewName
        // Detect preview providers (old)
        if node.inheritanceClause?.inheritedTypes.contains(where: { 
            $0.type.description.contains("PreviewProvider") 
        }) == true {
            detectedPreviews.insert(
                viewName.replacingOccurrences(of: "_Previews", with: "")
            )
        }
        // Detect #Preview macro (modern)
        if node.attributes.contains(where: { $0.description.contains("#Preview") }) {
            detectedPreviews.insert(viewName)
        }
        // Collect styling modifiers for this view
        stylingModifiers[currentViewName] = []
        return .visitChildren
    }

    override func visit(_ node: MacroExpansionExprSyntax) -> SyntaxVisitorContinueKind {
        // #Preview macro
        if node.macroName.text == "Preview" {
            for argument in node.arguments {
                if let expr = argument.expression.as(DeclReferenceExprSyntax.self) {
                    detectedPreviews.insert(expr.baseName.text)
                }
            }
        }
        return .visitChildren
    }

    override func visit(_ node: FunctionDeclSyntax) -> SyntaxVisitorContinueKind {
        if node.name.text == "body" {
            analyzeBodyForBasicErrorHandling(node)
        }
        return .visitChildren
    }

    override func visit(_ node: FunctionCallExprSyntax) -> SyntaxVisitorContinueKind {
        // Detect NavigationView nesting
        if let calledExpr = node.calledExpression.as(DeclReferenceExprSyntax.self),
           calledExpr.baseName.text == SwiftUIViewType.navigationView.rawValue {
            if navigationStack.contains(currentViewName) {
                addIssue(
                    severity: .warning,
                    message: "Nested NavigationView detected, this can cause issues",
                    filePath: currentFilePath,
                    lineNumber: getLineNumber(for: Syntax(node)),
                    suggestion: "Use NavigationStack or remove nested NavigationView",
                    ruleName: .nestedNavigationView
                )
            }
            navigationStack.append(currentViewName)
        }
        // Detect ForEach without ID (UI perspective)
        if let calledExpr = node.calledExpression.as(DeclReferenceExprSyntax.self),
           calledExpr.baseName.text == SwiftUIViewType.forEach.rawValue {
            var hasID = false
            for argument in node.arguments where argument.label?.text == "id" {
                hasID = true
            }
            if !hasID {
                addIssue(
                    severity: .warning,
                    message: "ForEach without explicit ID can cause performance issues",
                    filePath: currentFilePath,
                    lineNumber: getLineNumber(for: Syntax(node)),
                    suggestion: "Add an explicit id: parameter to ForEach",
                    ruleName: .forEachWithoutIDUI
                )
            }
        }
        // Detect inconsistent styling
        if let calledExpr = node.calledExpression.as(DeclReferenceExprSyntax.self),
           calledExpr.baseName.text == SwiftUIViewType.text.rawValue {
            let modifiers = collectStylingModifiers(node)

            // Only add styling modifiers that are actually styling-related
            let stylingModifierNames = [
                "font", "foregroundColor", "background", "padding",
                "cornerRadius", "shadow", "border"
            ]
            let stylingModifiers = modifiers.filter { stylingModifierNames.contains($0) }

            if stylingModifiers.count > 1 {
                addIssue(
                    severity: .info,
                    message: "Consider using consistent text styling",
                    filePath: currentFilePath,
                    lineNumber: getLineNumber(for: Syntax(node)),
                    suggestion: "Extract common styles into a ViewModifier or extension",
                    ruleName: .inconsistentStyling
                )
            }
        }
        return .visitChildren
    }

    override func visitPost(_ node: FunctionCallExprSyntax) {
        // Pop navigation stack if exiting NavigationView
        if let calledExpr = node.calledExpression.as(DeclReferenceExprSyntax.self),
           calledExpr.baseName.text == SwiftUIViewType.navigationView.rawValue {
            _ = navigationStack.popLast()
        }
    }

    override func visitPost(_ node: StructDeclSyntax) {
        // Check for missing preview for this view
        if isSwiftUIView(node) && !detectedPreviews.contains(currentViewName) {
            // Skip preview detection for test files
            if !currentFilePath.contains("test.swift")
                && !currentFilePath.contains("Test")
                && !currentFilePath.contains("Tests") {
                addIssue(
                    severity: .info,
                    message: "View '\(currentViewName)' missing preview provider",
                    filePath: currentFilePath,
                    lineNumber: getLineNumber(for: Syntax(node)),
                    suggestion: "Add a #Preview macro or PreviewProvider struct for better development experience",
                    ruleName: .missingPreview
                )
            }
        }
    }

    override func visit(_ node: VariableDeclSyntax) -> SyntaxVisitorContinueKind {
        // Look for computed property named 'body'
        for binding in node.bindings {
            guard let identifier = binding.pattern.as(IdentifierPatternSyntax.self),
                  identifier.identifier.text == "body" else { continue }

            if analyzeAccessorBlock(binding.accessorBlock, for: node) { continue }
            if analyzeInitializer(binding.initializer, for: node) { continue }
            analyzeBindingFallback(binding, for: node)
        }
        return .visitChildren
    }

    private func analyzeAccessorBlock(_ accessorBlock: AccessorBlockSyntax?, for node: VariableDeclSyntax) -> Bool {
        guard let accessorBlock = accessorBlock else { return false }
        for child in accessorBlock.accessors.children(viewMode: .all) {
            if let accessor = child.as(AccessorDeclSyntax.self), let body = accessor.body {
                analyzeBodyTextForErrorHandling(body.description, node: node)
                return true
            }
        }
        return false
    }

    private func analyzeInitializer(_ initializer: InitializerClauseSyntax?, for node: VariableDeclSyntax) -> Bool {
        guard let initializer = initializer else { return false }
        if let closure = initializer.value.as(ClosureExprSyntax.self) {
            analyzeBodyTextForErrorHandling(closure.statements.description, node: node)
            return true
        }
        return false
    }

    private func analyzeBindingFallback(_ binding: PatternBindingSyntax, for node: VariableDeclSyntax) {
        analyzeBodyTextForErrorHandling(binding.description, node: node)
    }

    private func analyzeBodyTextForErrorHandling(_ bodyText: String, node: VariableDeclSyntax) {
        let hasErrorHandling = bodyText.contains("if let error") || bodyText.contains("Text(\"Error")
        let hasProperUI = bodyText.contains(".alert(") || bodyText.contains(".sheet(") || bodyText.contains("Alert(")
        if hasErrorHandling && !hasProperUI {
            addIssue(
                severity: .info,
                message: "Consider using proper error handling UI patterns",
                filePath: currentFilePath,
                lineNumber: getLineNumber(for: Syntax(node)),
                suggestion: "Use .alert() or .sheet() modifiers for displaying errors",
                ruleName: .basicErrorHandling
            )
        }
    }

    // --- Helper Logic ---

    private func analyzeBodyForBasicErrorHandling(_ node: FunctionDeclSyntax) {
        guard let body = node.body else { return }
        let bodyText = body.description

        let hasErrorHandling = bodyText.contains("if let error") ||
            bodyText.contains("Text(\"Error")
        let hasProperUI = bodyText.contains(".alert(") ||
            bodyText.contains(".sheet(") ||
            bodyText.contains("Alert(")

        if hasErrorHandling && !hasProperUI {
            addIssue(
                severity: .info,
                message: "Consider using proper error handling UI patterns",
                filePath: currentFilePath,
                lineNumber: getLineNumber(for: Syntax(node)),
                suggestion: "Use .alert() or .sheet() modifiers for displaying errors",
                ruleName: .basicErrorHandling
            )
        }
    }

    private func collectStylingModifiers(_ node: FunctionCallExprSyntax) -> [String] {
        // Collect styling modifiers applied to this Text call
        var modifiers: Set<String> = []
        var current = node.parent

        while let parent = current {
            if let memberAccess = parent.as(MemberAccessExprSyntax.self) {
                modifiers.insert(memberAccess.declName.baseName.text)
            } else if let functionCall = parent.as(FunctionCallExprSyntax.self) {
                if let calledExpr = functionCall.calledExpression.as(MemberAccessExprSyntax.self) {
                    modifiers.insert(calledExpr.declName.baseName.text)
                }
            }
            current = parent.parent
        }

        return Array(modifiers)
    }

}
