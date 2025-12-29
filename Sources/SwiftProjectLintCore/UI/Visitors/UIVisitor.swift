import Foundation
import SwiftSyntax
// import SwiftSyntaxParser
import SwiftParser

/// Visitor for UI patterns (Navigation, preview, styling, ForEach without ID, error handling)
class UIVisitor: BasePatternVisitor {
    private var currentViewName: String = ""
    private var currentFilePath: String = ""
    private var previewStructs: Set<String> = []
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
        print("🔍 Visiting function: \(node.name.text)")
        // Search for error handling patterns in body
        if node.name.text == "body" {
            print("🔍 Found body function, analyzing for error handling")
            analyzeBodyForBasicErrorHandling(node)
        }
        return .visitChildren
    }

    override func visit(_ node: FunctionCallExprSyntax) -> SyntaxVisitorContinueKind {
        // Detect NavigationView nesting
        if let calledExpr = node.calledExpression.as(DeclReferenceExprSyntax.self),
           calledExpr.baseName.text == "NavigationView" {
            if navigationStack.contains(currentViewName) {
                addIssue(node: Syntax(node))
            }
            navigationStack.append(currentViewName)
        }
        // Detect ForEach without ID (UI perspective)
        if let calledExpr = node.calledExpression.as(DeclReferenceExprSyntax.self),
           calledExpr.baseName.text == "ForEach" {
            var hasID = false
            for argument in node.arguments {
                if argument.label?.text == "id" { 
                    hasID = true 
                }
            }
            if !hasID {
                addIssue(node: Syntax(node))
            }
        }
        // Detect inconsistent styling
        if let calledExpr = node.calledExpression.as(DeclReferenceExprSyntax.self),
           calledExpr.baseName.text == "Text" {
            let modifiers = collectStylingModifiers(node)

            // Only add styling modifiers that are actually styling-related
            let stylingModifierNames = [
                "font", "foregroundColor", "background", "padding",
                "cornerRadius", "shadow", "border"
            ]
            let stylingModifiers = modifiers.filter { stylingModifierNames.contains($0) }

            if stylingModifiers.count > 1 {
                addIssue(node: Syntax(node))
            }
        }
        return .visitChildren
    }

    override func visitPost(_ node: FunctionCallExprSyntax) {
        // Pop navigation stack if exiting NavigationView
        if let calledExpr = node.calledExpression.as(DeclReferenceExprSyntax.self),
           calledExpr.baseName.text == "NavigationView" {
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
                addIssue(node: Syntax(node), variables: ["viewName": currentViewName])
            }
        }
    }

    override func visit(_ node: VariableDeclSyntax) -> SyntaxVisitorContinueKind {
        // Look for computed property named 'body'
        for binding in node.bindings {
            print(
                "🔍 binding type: \(type(of: binding)), " +
                "description: \(binding.description)"
            )
            if let identifier = binding.pattern.as(IdentifierPatternSyntax.self),
               identifier.identifier.text == "body" {
                var analyzed = false
                if let accessorBlock = binding.accessorBlock {
                    for child in accessorBlock.accessors.children(viewMode: .all) {
                        if let accessor = child.as(AccessorDeclSyntax.self),
                           let body = accessor.body {
                            let bodyText = body.description
                            print(
                                "🔍 Analyzing computed property body for error handling: " +
                                "\(bodyText)"
                            )
                            let hasErrorHandling = bodyText.contains("if let error") ||
                                bodyText.contains("Text(\"Error")
                            let hasProperUI = bodyText.contains(".alert(") ||
                                bodyText.contains(".sheet(") ||
                                bodyText.contains("Alert(")
                            print("🔍 hasErrorHandling: \(hasErrorHandling), hasProperUI: \(hasProperUI)")
                            if hasErrorHandling && !hasProperUI {
                                addIssue(node: Syntax(node))
                            }
                            analyzed = true
                        }
                    }
                }
                if let initializer = binding.initializer {
                    print(
                        "🔍 initializer.value type: \(type(of: initializer.value)), " +
                        "description: \(initializer.value.description)"
                    )
                    if let value = initializer.value.as(CodeBlockSyntax.self) {
                        let bodyText = value.description
                        print(
                            "🔍 Analyzing computed property body for error handling: " +
                            "\(bodyText)"
                        )
                        let hasErrorHandling = bodyText.contains("if let error") ||
                            bodyText.contains("Text(\"Error")
                        let hasProperUI = bodyText.contains(".alert(") ||
                            bodyText.contains(".sheet(") ||
                            bodyText.contains("Alert(")
                        print("🔍 hasErrorHandling: \(hasErrorHandling), hasProperUI: \(hasProperUI)")
                        if hasErrorHandling && !hasProperUI {
                            addIssue(node: Syntax(node))
                        }
                        analyzed = true
                    }
                }
                // Always analyze the binding's description as a fallback
                if !analyzed {
                    let bodyText = binding.description
                    print(
                        "🔍 Fallback analyzing binding description for error handling: " +
                        "\(bodyText)"
                    )
                    let hasErrorHandling = bodyText.contains("if let error") ||
                        bodyText.contains("Text(\"Error")
                    let hasProperUI = bodyText.contains(".alert(") ||
                        bodyText.contains(".sheet(") ||
                        bodyText.contains("Alert(")
                    print("🔍 hasErrorHandling: \(hasErrorHandling), hasProperUI: \(hasProperUI)")
                    if hasErrorHandling && !hasProperUI {
                        addIssue(node: Syntax(node))
                    }
                }
            }
        }
        return .visitChildren
    }

    // --- Helper Logic ---

    private func analyzeBodyForBasicErrorHandling(_ node: FunctionDeclSyntax) {
        guard let body = node.body else { return }
        let bodyText = body.description

        // Debug logging
        print("🔍 Analyzing body for error handling: \(bodyText)")

        // Check if there's basic error handling without proper UI patterns
        let hasErrorHandling = bodyText.contains("if let error") ||
            bodyText.contains("Text(\"Error")
        let hasProperUI = bodyText.contains(".alert(") ||
            bodyText.contains(".sheet(") ||
            bodyText.contains("Alert(")

        print("🔍 hasErrorHandling: \(hasErrorHandling), hasProperUI: \(hasProperUI)")

        if hasErrorHandling && !hasProperUI {
            addIssue(node: Syntax(node))
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

        // Debug logging
        print("🔍 Collected modifiers for Text: \(Array(modifiers))")

        return Array(modifiers)
    }

    private func isSwiftUIView(_ node: StructDeclSyntax) -> Bool {
        for inheritance in node.inheritanceClause?.inheritedTypes ?? [] {
            if inheritance.type.as(IdentifierTypeSyntax.self)?.name.text == "View" {
                return true
            }
        }
        return false
    }
}
