import Foundation
import SwiftSyntax

// MARK: - Code Quality Visitor

/// A SwiftSyntax visitor that detects code quality issues in Swift code.
///
/// - Magic numbers in UI code
/// - Hardcoded strings that should be localized
/// - Long functions that should be broken down
/// - Missing documentation for public APIs
class CodeQualityVisitor: BasePatternVisitor {
    private var currentFunctionName: String = ""
    private var currentFunctionLength: Int = 0
    private var currentStructName: String = ""
    private var currentFilePath: String = ""
    private var isInFunction: Bool = false
    private var functionStartLine: Int = 0
    private var configuration: Configuration

    required init(pattern: SyntaxPattern, viewMode: SyntaxTreeViewMode = .sourceAccurate) {
        self.configuration = .default
        super.init(pattern: pattern, viewMode: viewMode)
    }

    /// Convenience initializer for tests and simple usage.
    convenience init(patternCategory: PatternCategory, configuration: Configuration = .default, viewMode: SyntaxTreeViewMode = .sourceAccurate) {
        let placeholder = SyntaxPattern(
            name: .unknown,
            visitor: CodeQualityVisitor.self,
            severity: .warning,
            category: patternCategory,
            messageTemplate: "",
            suggestion: "",
            description: ""
        )
        self.init(pattern: placeholder, viewMode: viewMode)
        self.configuration = configuration
    }

    /// Sets the current file path for issue reporting.
    override func setFilePath(_ filePath: String) {
        self.currentFilePath = filePath
    }

    override func visit(_ node: StructDeclSyntax) -> SyntaxVisitorContinueKind {
        let structName = node.name.text
        currentStructName = structName

        // Check for missing documentation on public structs
        if node.modifiers.contains(where: { $0.name.text == "public" }) {
            checkMissingDocumentation(for: Syntax(node), name: currentStructName)
        }

        return .visitChildren
    }

    override func visit(_ node: ClassDeclSyntax) -> SyntaxVisitorContinueKind {
        currentStructName = node.name.text

        // Check for missing documentation on public classes
        if node.modifiers.contains(where: { $0.name.text == "public" }) {
            checkMissingDocumentation(for: Syntax(node), name: currentStructName)
        }

        return .visitChildren
    }

    override func visit(_ node: FunctionDeclSyntax) -> SyntaxVisitorContinueKind {
        currentFunctionName = node.name.text
        isInFunction = true
        functionStartLine = getLineNumber(for: Syntax(node))
        // Count the main function body length in characters
        if let body = node.body {
            currentFunctionLength = body.description.count
        } else {
            currentFunctionLength = 0
        }
        // Check for missing documentation on public functions
        if configuration.checkPublicAPIsOnly {
            let modifiers = node.modifiers
            let isPublic = modifiers.contains { modifier in
                modifier.name.text == "public"
            }
            if isPublic {
                checkMissingDocumentation(for: Syntax(node), name: currentFunctionName)
            }
        } else {
            checkMissingDocumentation(for: Syntax(node), name: currentFunctionName)
        }
        return .visitChildren
    }

    override func visitPost(_ node: FunctionDeclSyntax) {
        // Check function length when leaving the function
        if isInFunction && currentFunctionLength > configuration.maxFunctionLength {
            addIssue(
                severity: .warning,
                message: "Function '\(currentFunctionName)' is quite long (\(currentFunctionLength) characters)",
                filePath: currentFilePath,
                lineNumber: functionStartLine,
                suggestion: "Consider breaking this function into smaller, focused functions",
                ruleName: .longFunction
            )
        }
        // Reset function tracking
        isInFunction = false
        currentFunctionLength = 0
        currentFunctionName = ""
    }

    override func visit(_ node: VariableDeclSyntax) -> SyntaxVisitorContinueKind {
        // Check for magic numbers in UI-related properties
        for binding in node.bindings {
            if let initializer = binding.initializer {
                // Look for integer or float literals directly
                if let intLiteral = initializer.value.as(IntegerLiteralExprSyntax.self) {
                    let value = Int(intLiteral.literal.text) ?? 0
                    if value >= configuration.magicNumberThreshold {
                        addIssue(
                            severity: .info,
                            message: "Consider extracting magic number \(value) to a named constant",
                            filePath: currentFilePath,
                            lineNumber: getLineNumber(for: Syntax(initializer)),
                            suggestion: "Extract \(value) to a named constant for better maintainability",
                            ruleName: .magicNumber
                        )
                    }
                } else if let floatLiteral = initializer.value.as(FloatLiteralExprSyntax.self) {
                    if let value = Double(floatLiteral.literal.text),
                       value >= Double(configuration.magicNumberThreshold) {
                        addIssue(
                            severity: .info,
                            message: "Consider extracting magic number \(value) to a named constant",
                            filePath: currentFilePath,
                            lineNumber: getLineNumber(for: Syntax(initializer)),
                            suggestion: "Extract \(value) to a named constant for better maintainability",
                            ruleName: .magicNumber
                        )
                    }
                }
            }
        }
        return .visitChildren
    }

    override func visit(_ node: FunctionCallExprSyntax) -> SyntaxVisitorContinueKind {
        // Check for magic numbers in function call arguments
        for argument in node.arguments {
            if let intLiteral = argument.expression.as(IntegerLiteralExprSyntax.self) {
                let value = Int(intLiteral.literal.text) ?? 0
                if value >= configuration.magicNumberThreshold {
                    addIssue(
                        severity: .info,
                        message: "Consider extracting magic number \(value) to a named constant",
                        filePath: currentFilePath,
                        lineNumber: getLineNumber(for: Syntax(argument)),
                        suggestion: "Extract \(value) to a named constant for better maintainability",
                        ruleName: .magicNumber
                    )
                }
            } else if let floatLiteral = argument.expression.as(FloatLiteralExprSyntax.self) {
                if let value = Double(floatLiteral.literal.text), value >= Double(configuration.magicNumberThreshold) {
                    addIssue(
                        severity: .info,
                        message: "Consider extracting magic number \(value) to a named constant",
                        filePath: currentFilePath,
                        lineNumber: getLineNumber(for: Syntax(argument)),
                        suggestion: "Extract \(value) to a named constant for better maintainability",
                        ruleName: .magicNumber
                    )
                }
            }
        }
        return .visitChildren
    }

    /// SwiftUI initializers and modifiers whose string arguments are shown to users.
    private static let userFacingCallNames: Set<String> = [
        "Text", "Label", "Button", "Toggle", "Picker", "Slider",
        "Section", "NavigationLink", "TabItem", "DisclosureGroup",
        "navigationTitle", "navigationBarTitle",
        "alert", "confirmationDialog",
        "headerProminence", "badge",
        "help", "toolbarItem"
    ]

    override func visit(_ node: StringLiteralExprSyntax) -> SyntaxVisitorContinueKind {
        // Only flag hardcoded strings that appear in user-facing SwiftUI contexts
        // (Text, Label, Button title, alert, navigationTitle, etc.)
        let segments = node.segments
        guard segments.count == 1,
              let segment = segments.first?.as(StringSegmentSyntax.self) else {
            return .visitChildren
        }
        let cleanString = segment.content.text
        guard !cleanString.isEmpty,
              !cleanString.contains("\\"),
              isInUserFacingContext(node) else {
            return .visitChildren
        }

        let skipPatterns = [
            "http", "https", "file://", "data:", "base64"
        ]
        let shouldSkip = skipPatterns.contains { cleanString.contains($0) }
        if !shouldSkip {
            addIssue(
                severity: .info,
                message: "Consider localizing hardcoded text: \"\(cleanString)\"",
                filePath: currentFilePath,
                lineNumber: getLineNumber(for: Syntax(node)),
                suggestion: "Use NSLocalizedString or String(localized:) for user-facing text",
                ruleName: .hardcodedStrings
            )
        }
        return .visitChildren
    }

    /// Checks whether a string literal is a direct argument to a user-facing SwiftUI call.
    private func isInUserFacingContext(_ node: StringLiteralExprSyntax) -> Bool {
        // Walk up to the nearest FunctionCallExprSyntax ancestor
        var current: Syntax = Syntax(node)
        while let parent = current.parent {
            if let call = parent.as(FunctionCallExprSyntax.self) {
                // Check DeclReferenceExpr: Text("hello"), Button("tap") etc.
                if let ref = call.calledExpression.as(DeclReferenceExprSyntax.self),
                   Self.userFacingCallNames.contains(ref.baseName.text) {
                    return true
                }
                // Check MemberAccessExpr: .navigationTitle("hello"), .alert("title") etc.
                if let member = call.calledExpression.as(MemberAccessExprSyntax.self),
                   Self.userFacingCallNames.contains(member.declName.baseName.text) {
                    return true
                }
            }
            // Stop climbing at the enclosing declaration to avoid false positives
            if parent.is(FunctionDeclSyntax.self)
                || parent.is(VariableDeclSyntax.self)
                || parent.is(StructDeclSyntax.self)
                || parent.is(ClassDeclSyntax.self) {
                break
            }
            current = parent
        }
        return false
    }

    // MARK: - Private Detection Methods

    private func checkMissingDocumentation(for node: Syntax, name: String) {
        // Check if the node has documentation comments
        let leadingTrivia = node.leadingTrivia

        let hasDocumentation = leadingTrivia.contains { piece in
            switch piece {
            case .docLineComment, .docBlockComment:
                return true
            default:
                return false
            }
        }

        if !hasDocumentation {
            addIssue(
                severity: .info,
                message: "Missing documentation for '\(name)'",
                filePath: currentFilePath,
                lineNumber: getLineNumber(for: node),
                suggestion: "Add documentation comments to describe the purpose and usage",
                ruleName: .missingDocumentation
            )
        }
    }
}

// MARK: - Code Quality Pattern Extensions

extension CodeQualityVisitor {
    /// Configuration for code quality detection.
    struct Configuration {
        let maxFunctionLength: Int
        let magicNumberThreshold: Int
        let checkPublicAPIsOnly: Bool

        static let `default` = Configuration(
            maxFunctionLength: 200,
            magicNumberThreshold: 10,
            checkPublicAPIsOnly: true
        )

        static let strict = Configuration(
            maxFunctionLength: 150,
            magicNumberThreshold: 5,
            checkPublicAPIsOnly: false
        )
    }
}
