import SwiftProjectLintModels
import SwiftProjectLintRegistry
import SwiftProjectLintVisitors
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
    /// The first View-conforming struct in the file — only this view is checked for a missing preview.
    private var primaryViewName: String?

    required init(pattern: SyntaxPattern, viewMode: SyntaxTreeViewMode = .sourceAccurate) {
        super.init(pattern: pattern, viewMode: viewMode)
    }

    override func setFilePath(_ filePath: String) {
        self.currentFilePath = filePath
    }

    override func visit(_ node: StructDeclSyntax) -> SyntaxVisitorContinueKind {
        let viewName = node.name.text
        currentViewName = viewName
        // Track the first View struct as the primary view for preview checks
        // Exclude App structs — previewing the app entry point is not standard practice
        if primaryViewName == nil, isSwiftUIViewOnly(node) {
            primaryViewName = viewName
        }
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
                // Suppress when the element type is known to be Identifiable
                let elementType = inferForEachElementType(node)
                let isIdentifiable = elementType.map { knownIdentifiableTypes.contains($0) } ?? false

                if !isIdentifiable {
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
        }
        // Detect inconsistent styling
        if let calledExpr = node.calledExpression.as(DeclReferenceExprSyntax.self),
           calledExpr.baseName.text == SwiftUIViewType.text.rawValue {
            let modifiers = collectStylingModifiers(node)

            // Only count visual styling modifiers — not layout (padding, cornerRadius)
            let stylingModifierNames: Set<String> = [
                "font", "foregroundColor", "foregroundStyle",
                "background", "shadow", "border",
                "bold", "italic", "underline", "strikethrough",
                "fontWeight", "fontDesign"
            ]
            let stylingModifiers = modifiers.filter { stylingModifierNames.contains($0) }

            if stylingModifiers.count > 3 {
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
        // Only check the primary (first) view in the file for missing preview.
        // Subcomponent views in the same file are covered by the primary view's preview.
        let viewName = node.name.text
        if isSwiftUIViewOnly(node),
           viewName == primaryViewName,
           !detectedPreviews.contains(viewName),
           !hasComplexDependencies(node) {
            // Skip test files
            if currentFilePath.contains("test.swift")
                || currentFilePath.contains("Test")
                || currentFilePath.contains("Tests") {
                return
            }
            // Skip helper/extension files
            if currentFilePath.hasSuffix("+Extensions.swift")
                || currentFilePath.contains("Helper.swift") {
                return
            }
            // Skip private/fileprivate views (small helper views)
            if hasRestrictedAccess(node) { return }
            // Skip trivial views (body < 4 source lines including braces)
            let bodyLineCount = countBodyLines(node)
            if bodyLineCount < 4 { return }

            let severity = previewSeverity(for: node)
            addIssue(
                severity: severity,
                message: "View '\(viewName)' missing preview provider",
                filePath: currentFilePath,
                lineNumber: getLineNumber(for: Syntax(node)),
                suggestion: "Add a #Preview macro or PreviewProvider struct "
                    + "for better development experience",
                ruleName: .missingPreview
            )
        }
    }

    /// Returns tiered severity based on view access level.
    private func previewSeverity(for node: StructDeclSyntax) -> IssueSeverity {
        let hasPublicAccess = node.modifiers.contains { modifier in
            let text = modifier.name.text
            return text == "public" || text == "open"
        }
        return hasPublicAccess ? .warning : .info
    }

    /// Returns true if the view is private or fileprivate.
    private func hasRestrictedAccess(_ node: StructDeclSyntax) -> Bool {
        node.modifiers.contains { modifier in
            let text = modifier.name.text
            return text == "private" || text == "fileprivate"
        }
    }

    /// Counts the approximate source lines of the body property.
    private func countBodyLines(_ node: StructDeclSyntax) -> Int {
        for member in node.memberBlock.members {
            guard let varDecl = member.decl.as(VariableDeclSyntax.self) else { continue }
            for binding in varDecl.bindings {
                guard let name = binding.pattern.as(IdentifierPatternSyntax.self),
                      name.identifier.text == "body",
                      let accessorBlock = binding.accessorBlock else { continue }
                let bodyText = accessorBlock.trimmedDescription
                let lines = bodyText.split(separator: "\n", omittingEmptySubsequences: true)
                    .filter { $0.trimmingCharacters(in: .whitespaces).isEmpty == false }
                return lines.count
            }
        }
        return 0
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

    // --- Dependency Detection ---

    /// Returns true if the view uses `@Environment`, `@EnvironmentObject`, `@Bindable`,
    /// or has a property whose type name contains "ViewModel". Views with these
    /// dependencies require non-trivial mock setup for previews, so the missing-preview
    /// rule only flags leaf components without them.
    private func hasComplexDependencies(_ node: StructDeclSyntax) -> Bool {
        let complexWrappers: Set<String> = ["Environment", "EnvironmentObject", "Bindable"]

        for member in node.memberBlock.members {
            guard let varDecl = member.decl.as(VariableDeclSyntax.self) else { continue }

            // Check property wrapper attributes
            for attribute in varDecl.attributes {
                guard let attr = attribute.as(AttributeSyntax.self),
                      let attrName = attr.attributeName.as(IdentifierTypeSyntax.self)?.name.text
                else { continue }
                if complexWrappers.contains(attrName) {
                    return true
                }
            }

            // Check for ViewModel-typed properties
            for binding in varDecl.bindings {
                if let typeAnnotation = binding.typeAnnotation {
                    let typeText = typeAnnotation.type.description.trimmingCharacters(in: .whitespaces)
                    if typeText.contains("ViewModel") {
                        return true
                    }
                }
            }
        }
        return false
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
        // Collect styling modifiers applied directly to this Text call.
        // Walk up through the modifier chain (Text("x").font(.title).foregroundColor(.blue))
        // but stop when we hit a closure body, code block, or container view — those modifiers
        // belong to the enclosing view, not this Text.
        var modifiers: Set<String> = []
        var current: Syntax = Syntax(node)

        while let parent = current.parent {
            // Stop at closure/code block boundaries — modifiers above here belong to a container
            if parent.is(CodeBlockItemSyntax.self)
                || parent.is(ClosureExprSyntax.self) {
                break
            }

            if let functionCall = parent.as(FunctionCallExprSyntax.self),
               let calledExpr = functionCall.calledExpression.as(MemberAccessExprSyntax.self) {
                modifiers.insert(calledExpr.declName.baseName.text)
            }

            current = parent
        }

        return Array(modifiers)
    }

}
