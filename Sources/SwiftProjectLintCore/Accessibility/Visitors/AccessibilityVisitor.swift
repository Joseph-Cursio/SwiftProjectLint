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
    internal var config: Configuration

    /// The current file path.
    private var currentFilePath: String?

    /// Track Images that are part of Buttons to avoid duplicate issues
    private var imagesInButtons: Set<Syntax> = []

    // MARK: - Internal Access Methods for Checkers

    /// Get the current pattern for issue reporting
    internal var currentPattern: SyntaxPattern? {
        return pattern
    }

    /// Get the current file path for issue reporting
    internal func getCurrentFilePath() -> String? {
        return currentFilePath
    }

    /// Add images found in buttons to avoid duplicate issues
    internal func addImagesInButtons(_ images: Set<Syntax>) {
        imagesInButtons.formUnion(images)
    }

    /// Check if an image is already part of a button
    internal func isImageInButtons(_ image: Syntax) -> Bool {
        return imagesInButtons.contains(image)
    }

    // MARK: - Accessibility Checkers

    private lazy var buttonChecker = ButtonAccessibilityChecker(visitor: self)
    private lazy var imageChecker = ImageAccessibilityChecker(visitor: self)
    private lazy var textChecker = TextAccessibilityChecker(visitor: self)
    private lazy var colorChecker = ColorAccessibilityChecker(visitor: self)
    private lazy var customControlChecker = CustomControlAccessibilityChecker(visitor: self)

    // MARK: - Initializers

    required init(pattern: SyntaxPattern, viewMode: SyntaxTreeViewMode = .sourceAccurate) {
        self.config = .default
        super.init(pattern: pattern, viewMode: viewMode)
    }

    /// Convenience initializer for tests with custom configuration.
    convenience init(config: Configuration, viewMode: SyntaxTreeViewMode = .sourceAccurate) {
        let placeholder = SyntaxPattern(
            name: .unknown,
            visitor: AccessibilityVisitor.self,
            severity: .warning,
            category: .accessibility,
            messageTemplate: "",
            suggestion: "",
            description: ""
        )
        self.init(pattern: placeholder, viewMode: viewMode)
        self.config = config
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
        DebugLogger.logNode(
            "FunctionCallExpr",
            "name: \(node.calledExpression.description.trimmingCharacters(in: .whitespaces))")

        // Check if this is a Button, Image, or Text
        if let calledExpression = node.calledExpression.as(DeclReferenceExprSyntax.self) {
            let functionName = calledExpression.baseName.text

            if functionName == "Button" {
                DebugLogger.logVisitor(.accessibility, "Found Button initialization")
                buttonChecker.checkAccessibility(node)
            } else if functionName == "Image" {
                DebugLogger.logVisitor(.accessibility, "Found Image initialization")
                imageChecker.checkAccessibility(node)
            } else if functionName == "Text" {
                DebugLogger.logVisitor(.accessibility, "Found Text initialization")
                textChecker.checkAccessibility(node)
            }
        }

        return .visitChildren
    }

    override func visit(_ node: MemberAccessExprSyntax) -> SyntaxVisitorContinueKind {
        DebugLogger.logNode("MemberAccessExpr", "name: \(node.declName.baseName.text)")

        // Check for color usage
        colorChecker.checkAccessibility(node)

        return .visitChildren
    }

    override func visit(_ node: VariableDeclSyntax) -> SyntaxVisitorContinueKind {
        // Check for custom controls without accessibility traits
        customControlChecker.checkAccessibility(node)

        return .visitChildren
    }

    override func visit(_ node: SourceFileSyntax) -> SyntaxVisitorContinueKind {
        // Set a default file path since we can't extract it from SourceFileSyntax
        currentFilePath = "unknown"
        return .visitChildren
    }

    // MARK: - Helper Methods

    // All helper methods have been moved to their respective checker classes
    // to improve separation of concerns and maintainability.
}
