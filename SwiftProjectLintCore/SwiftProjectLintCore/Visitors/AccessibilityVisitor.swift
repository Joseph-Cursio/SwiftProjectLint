import Foundation
import SwiftSyntax
import SwiftParser

/// A visitor that analyzes Swift code for accessibility-related issues using SwiftSyntax AST.
///
/// This visitor detects common accessibility problems such as:
/// - Missing accessibility labels for buttons with images
/// - Missing accessibility hints for interactive elements
/// - Missing accessibility traits for custom controls
/// - Inaccessible color usage
///
/// Example usage:
/// ```swift
/// let visitor = AccessibilityVisitor()
/// let sourceFile = Parser.parse(source: sourceCode)
/// visitor.walk(sourceFile)
/// let issues = visitor.detectedIssues
/// ```
class AccessibilityVisitor: BasePatternVisitor {
    
    // MARK: - Configuration
    
    /// Configuration for the accessibility visitor.
    struct Configuration {
        /// Minimum text length to suggest accessibility hints.
        let minTextLengthForHint: Int
        
        /// Default configuration.
        static let `default` = Configuration(minTextLengthForHint: 50)
    }
    
    /// The configuration for this visitor.
    internal let config: Configuration
    
    /// The current file path.
    internal var currentFilePath: String?
    
    /// Track Images that are part of Buttons to avoid duplicate issues
    internal var imagesInButtons: Set<Syntax> = []
    
    // MARK: - Initializers
    
    /// Creates a new accessibility visitor with the specified configuration.
    /// - Parameter config: The configuration for accessibility checking.
    init(config: Configuration = .default, viewMode: SyntaxTreeViewMode = .sourceAccurate) {
        self.config = config
        super.init(viewMode: viewMode)
    }
    
    required init(patternCategory: PatternCategory) {
        self.config = .default
        super.init(viewMode: .sourceAccurate)
    }
    
    required init(viewMode: SyntaxTreeViewMode) {
        self.config = .default
        super.init(viewMode: viewMode)
    }
    
    override func reset() {
        super.reset()
        imagesInButtons.removeAll()
    }
    
    // MARK: - File Path Setter
    
    /// Sets the current file path.
    /// - Parameter filePath: The path to the current file.
    override func setFilePath(_ filePath: String) {
        self.currentFilePath = filePath
    }
    
    // MARK: - Syntax Visitor Methods
    
    override func visit(_ node: FunctionCallExprSyntax) -> SyntaxVisitorContinueKind {
        Task { @MainActor in
            DebugLogger.logNode("FunctionCallExpr", "name: \(node.calledExpression.description.trimmingCharacters(in: .whitespaces))")
        }
        
        // Check if this is a Button, Image, or Text
        if let calledExpression = node.calledExpression.as(DeclReferenceExprSyntax.self) {
            let functionName = calledExpression.baseName.text
            
            if functionName == "Button" {
                Task { @MainActor in
                    DebugLogger.logVisitor(.accessibility, "Found Button initialization")
                }
                checkButtonAccessibility(node)
            } else if functionName == "Image" {
                Task { @MainActor in
                    DebugLogger.logVisitor(.accessibility, "Found Image initialization")
                }
                checkImageAccessibility(node)
            } else if functionName == "Text" {
                Task { @MainActor in
                    DebugLogger.logVisitor(.accessibility, "Found Text initialization")
                }
                checkTextAccessibility(node)
            }
        }
        
        return .visitChildren
    }
    
    override func visit(_ node: MemberAccessExprSyntax) -> SyntaxVisitorContinueKind {
        Task { @MainActor in
            DebugLogger.logNode("MemberAccessExpr", "name: \(node.declName.baseName.text)")
        }
        
        // Check for color usage
        checkInaccessibleColorUsage(node)
        
        return .visitChildren
    }
    
    override func visit(_ node: VariableDeclSyntax) -> SyntaxVisitorContinueKind {
        // Check for custom controls without accessibility traits
        checkCustomControlMissingTraits(node)
        
        return .visitChildren
    }
    
    override func visit(_ node: SourceFileSyntax) -> SyntaxVisitorContinueKind {
        // Set a default file path since we can't extract it from SourceFileSyntax
        currentFilePath = "unknown"
        return .visitChildren
    }
    
    // MARK: - Helper Methods
    
    private func checkButtonAccessibility(_ node: FunctionCallExprSyntax) {
        // Track Images found in this Button
        let imagesInThisButton = findImagesInSyntax(Syntax(node))
        imagesInButtons.formUnion(imagesInThisButton)
        
        // Check if button contains an Image
        if containsImage(node) {
            if !hasAccessibilityModifierInExpressionTree(node, "accessibilityLabel") {
                addIssue(
                    severity: .warning,
                    message: "Button with image missing accessibility label",
                    filePath: currentFilePath ?? "unknown",
                    lineNumber: getLineNumber(for: Syntax(node)),
                    suggestion: "Add .accessibilityLabel(\"description\") to provide context for screen readers",
                    ruleName: currentPattern?.name
                )
            }
        }
        // Check if button contains Text
        if containsText(node) {
            if !hasAccessibilityModifierInExpressionTree(node, "accessibilityHint") {
                addIssue(
                    severity: .info,
                    message: "Consider adding accessibility hint to button with text",
                    filePath: currentFilePath ?? "unknown",
                    lineNumber: getLineNumber(for: Syntax(node)),
                    suggestion: "Add .accessibilityHint(\"description\") to provide additional context",
                    ruleName: currentPattern?.name
                )
            }
        }
    }
    
    private func checkImageAccessibility(_ node: FunctionCallExprSyntax) {
        // Skip if this Image is already part of a Button
        if imagesInButtons.contains(Syntax(node)) {
            return
        }
        
        if !hasAccessibilityModifierInExpressionTree(node, "accessibilityLabel") {
            addIssue(
                severity: .warning,
                message: "Image missing accessibility label",
                filePath: currentFilePath ?? "unknown",
                lineNumber: getLineNumber(for: Syntax(node)),
                suggestion: "Add .accessibilityLabel(\"descriptive text\") to make the image accessible to screen readers",
                ruleName: currentPattern?.name
            )
        }
    }
    
    private func checkTextAccessibility(_ node: FunctionCallExprSyntax) {
        Task { @MainActor in
            DebugLogger.logVisitor(.accessibility, "checkTextAccessibility called")
        }
        
        // Check if the text is long enough to warrant accessibility features
        if let argument = node.arguments.first,
           let stringLiteral = argument.expression.as(StringLiteralExprSyntax.self) {
            let text = stringLiteral.segments.compactMap { segment in
                if case .stringSegment(let stringSegment) = segment {
                    return stringSegment.content.text
                }
                return nil
            }.joined()
            let threshold = config.minTextLengthForHint
            Task { @MainActor in
                DebugLogger.logVisitor(.accessibility, "Checking text: '\(text)' with length \(text.count), threshold: \(threshold)")
            }
            
            if isLongText(text) {
                Task { @MainActor in
                    DebugLogger.logVisitor(.accessibility, "Text is long, checking for accessibility modifier")
                }
                
                // Check if there's an accessibility modifier in the expression tree
                if hasAccessibilityModifierInExpressionTree(node, "accessibilityLabel") ||
                   hasAccessibilityModifierInExpressionTree(node, "accessibilityHint") ||
                   hasAccessibilityModifierInExpressionTree(node, "accessibilityValue") {
                    Task { @MainActor in
                        DebugLogger.logVisitor(.accessibility, "Text has accessibility modifier, skipping")
                    }
                    return
                }
                
                Task { @MainActor in
                    DebugLogger.logIssue("Long text without accessibility features")
                }
                let filePath = currentFilePath ?? "unknown"
                let lineNumber = getLineNumber(for: Syntax(node))
                let ruleName = currentPattern?.name
                addIssue(
                    severity: .info,
                    message: "Long text content may benefit from accessibility features",
                    filePath: filePath,
                    lineNumber: lineNumber,
                    suggestion: "Add .accessibilityLabel(), .accessibilityHint(), or .accessibilityValue() to improve accessibility.",
                    ruleName: ruleName
                )
            }
        }
    }
    
    private func containsImage(_ node: FunctionCallExprSyntax) -> Bool {
        // Search recursively through the entire Button node
        if containsImageInSyntax(Syntax(node)) {
            return true
        }
        
        // Check arguments for Image
        for argument in node.arguments {
            // Check if the argument expression is a function call to Image
            if let functionCall = argument.expression.as(FunctionCallExprSyntax.self),
               let calledExpression = functionCall.calledExpression.as(DeclReferenceExprSyntax.self),
               calledExpression.baseName.text == "Image" {
                return true
            }
            // Check if this is a label parameter with a closure (e.g., label: { Image("icon") })
            if let labelExpr = argument.expression.as(ClosureExprSyntax.self) {
                if containsImageInClosure(labelExpr) {
                    return true
                }
            }
        }
        // Check trailing closure for Image
        if let trailingClosure = node.trailingClosure {
            if containsImageInClosure(trailingClosure) {
                return true
            }
        }
        return false
    }
    
    private func containsImageInClosure(_ closure: ClosureExprSyntax) -> Bool {
        for statement in closure.statements {
            if containsImageInSyntax(Syntax(statement.item)) {
                return true
            }
        }
        return false
    }

    private func containsImageInSyntax(_ syntax: Syntax) -> Bool {
        if let functionCall = syntax.as(FunctionCallExprSyntax.self),
           let calledExpression = functionCall.calledExpression.as(DeclReferenceExprSyntax.self),
           calledExpression.baseName.text == "Image" {
            return true
        }
        for child in syntax.children(viewMode: .sourceAccurate) {
            if containsImageInSyntax(child) {
                return true
            }
        }
        return false;
    }
    
    /// Checks if the function call contains a Text element
    func containsText(_ node: FunctionCallExprSyntax) -> Bool {
        // Search recursively through the entire Button node
        if containsTextInSyntax(Syntax(node)) {
            return true
        }
        
        // Check arguments for Text
        for argument in node.arguments {
            if let functionCall = argument.expression.as(FunctionCallExprSyntax.self),
               let calledExpression = functionCall.calledExpression.as(DeclReferenceExprSyntax.self),
               calledExpression.baseName.text == "Text" {
                return true
            }
        }
        
        // Check trailing closure for Text
        if let trailingClosure = node.trailingClosure {
            if containsTextInClosure(trailingClosure) {
                return true
            }
        }
        
        return false
    }
    
    private func containsTextInClosure(_ closure: ClosureExprSyntax) -> Bool {
        for statement in closure.statements {
            if containsTextInSyntax(Syntax(statement.item)) {
                return true
            }
        }
        return false
    }

    private func containsTextInSyntax(_ syntax: Syntax) -> Bool {
        if let functionCall = syntax.as(FunctionCallExprSyntax.self),
           let calledExpression = functionCall.calledExpression.as(DeclReferenceExprSyntax.self),
           calledExpression.baseName.text == "Text" {
            return true
        }
        for child in syntax.children(viewMode: .sourceAccurate) {
            if containsTextInSyntax(child) {
                return true
            }
        }
        return false;
    }
    
    private func isLongText(_ text: String) -> Bool {
        let threshold = config.minTextLengthForHint
        Task { @MainActor in
            DebugLogger.logVisitor(.accessibility, "isLongText called with \(text.count) characters")
            DebugLogger.logVisitor(.accessibility, "isLongText - checking text: '\(text)' with length \(text.count), threshold: \(threshold)")
        }
        let result = text.count > threshold
        Task { @MainActor in
            DebugLogger.logVisitor(.accessibility, "isLongText - returning \(result) for long text")
        }
        return result
    }
    
    /// Checks if the given modifier exists anywhere in the modifier chain (hybrid traversal: parent chain + recursive base)
    private func hasAccessibilityModifierInExpressionTree(_ node: FunctionCallExprSyntax, _ modifierName: String) -> Bool {
        let accessibilityModifiers: Set<String> = [
            "accessibilityLabel",
            "accessibilityHint",
            "accessibilityValue",
            "accessibilityIdentifier",
            "accessibilityAddTraits",
            "accessibilityRemoveTraits",
            "accessibilitySortPriority",
            "accessibilityHidden",
            "accessibilityElement",
            "accessibilityAction",
            "accessibilityAdjustableAction",
            "accessibilityCustomAction",
            "accessibilityRespondsToUserInteraction"
        ]
        guard accessibilityModifiers.contains(modifierName) else { return false }
        
        // Recursively check the base of MemberAccessExprSyntax and calledExpression of FunctionCallExprSyntax
        func recursiveBaseTraversal(_ syntax: Syntax) -> Bool {
            if let functionCall = syntax.as(FunctionCallExprSyntax.self) {
                // Check for direct call (e.g., .accessibilityLabel(...))
                if let calledExpression = functionCall.calledExpression.as(DeclReferenceExprSyntax.self),
                   calledExpression.baseName.text == modifierName {
                    return true
                }
                // Check for member access (e.g., .accessibilityLabel)
                if let memberAccess = functionCall.calledExpression.as(MemberAccessExprSyntax.self),
                   memberAccess.declName.baseName.text == modifierName {
                    return true
                }
                // Recursively check the calledExpression
                if recursiveBaseTraversal(Syntax(functionCall.calledExpression)) {
                    return true
                }
                // Recursively check the arguments
                for argument in functionCall.arguments {
                    if recursiveBaseTraversal(Syntax(argument.expression)) {
                        return true
                    }
                }
                // Recursively check the trailing closure
                if let trailingClosure = functionCall.trailingClosure {
                    if recursiveBaseTraversal(Syntax(trailingClosure)) {
                        return true
                    }
                }
            } else if let memberAccess = syntax.as(MemberAccessExprSyntax.self) {
                if memberAccess.declName.baseName.text == modifierName {
                    return true
                }
                // Recursively check the base of the member access
                if let base = memberAccess.base {
                    if recursiveBaseTraversal(Syntax(base)) {
                        return true
                    }
                }
            } else if let closure = syntax.as(ClosureExprSyntax.self) {
                for statement in closure.statements {
                    if recursiveBaseTraversal(Syntax(statement.item)) {
                        return true
                    }
                }
            }
            return false
        }
        
        // Traverse up the parent chain, and at each node, do recursive base traversal
        var current: Syntax? = Syntax(node)
        while let syntax = current {
            if recursiveBaseTraversal(syntax) {
                return true
            }
            current = syntax.parent
        }
        return false
    }
    
    private func checkInaccessibleColorUsage(_ node: MemberAccessExprSyntax) {
        // Check for Color usage without accessibility features
        if let base = node.base?.as(DeclReferenceExprSyntax.self),
           base.baseName.text == "Color" {
            addIssue(
                severity: .info,
                message: "Consider accessibility when using color-based information",
                filePath: currentFilePath ?? "unknown",
                lineNumber: getLineNumber(for: Syntax(node)),
                suggestion: "Ensure color is not the only way information is conveyed. Add text labels, icons, or patterns.",
                ruleName: currentPattern?.name
            )
        }
        
        // Check for foregroundColor usage
        if node.declName.baseName.text == "foregroundColor" {
            // Check if there are accessibility modifiers present that would make color usage acceptable
            if let parent = node.parent,
               let functionCall = parent.as(FunctionCallExprSyntax.self) {
                // If there are accessibility modifiers, skip the color issue
                if hasAccessibilityModifierInExpressionTree(functionCall, "accessibilityLabel") ||
                   hasAccessibilityModifierInExpressionTree(functionCall, "accessibilityHint") ||
                   hasAccessibilityModifierInExpressionTree(functionCall, "accessibilityValue") {
                    return // Skip color issue if accessibility modifiers are present
                }
            }
            
            addIssue(
                severity: .info,
                message: "Consider accessibility when using color-based information",
                filePath: currentFilePath ?? "unknown",
                lineNumber: getLineNumber(for: Syntax(node)),
                suggestion: "Ensure color is not the only way information is conveyed. Add text labels, icons, or patterns.",
                ruleName: currentPattern?.name
            )
        }
    }
    
    /// Checks for custom controls that might be missing accessibility traits.
    private func checkCustomControlMissingTraits(_ node: VariableDeclSyntax) {
        // Would check for custom view types that should have accessibility traits
        // This is a placeholder for future implementation
    }
    
    private func findImagesInSyntax(_ syntax: Syntax) -> Set<Syntax> {
        var images: Set<Syntax> = []
        
        if let functionCall = syntax.as(FunctionCallExprSyntax.self),
           let calledExpression = functionCall.calledExpression.as(DeclReferenceExprSyntax.self),
           calledExpression.baseName.text == "Image" {
            images.insert(syntax)
        }
        
        for child in syntax.children(viewMode: .sourceAccurate) {
            images.formUnion(findImagesInSyntax(child))
        }
        
        return images
    }
} 
