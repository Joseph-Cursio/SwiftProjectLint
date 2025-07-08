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
    private var isInViewBody: Bool = false
    private var isInFunction: Bool = false
    private var functionStartLine: Int = 0
    private let configuration: Configuration
    
    init(patternCategory: PatternCategory, configuration: Configuration = .default) {
        self.configuration = configuration
        super.init(viewMode: .sourceAccurate)
    }
    
    required init(patternCategory: PatternCategory) {
        self.configuration = .default
        super.init(viewMode: .sourceAccurate)
    }
    
    required init(viewMode: SyntaxTreeViewMode) {
        self.configuration = .default
        super.init(viewMode: viewMode)
    }
    
    /// Sets the current file path for issue reporting.
    override func setFilePath(_ filePath: String) {
        self.currentFilePath = filePath
    }
    
    override func visit(_ node: StructDeclSyntax) -> SyntaxVisitorContinueKind {
        currentStructName = node.name.text
        
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
        // Debug print for function length (using NSLog)
        NSLog("[DEBUG] Function '%@' length: %d (threshold: %d)", currentFunctionName, currentFunctionLength, configuration.maxFunctionLength)
        // Check function length when leaving the function
        if isInFunction && currentFunctionLength > configuration.maxFunctionLength {
            addIssue(
                severity: .warning,
                message: "Function '\(currentFunctionName)' is quite long (\(currentFunctionLength) characters), consider breaking it down into smaller functions",
                filePath: currentFilePath,
                lineNumber: functionStartLine,
                suggestion: "Break down long functions into smaller, more focused functions for better maintainability",
                ruleName: currentPattern?.name
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
                            message: "Consider extracting magic number \(value) into a named constant",
                            filePath: currentFilePath,
                            lineNumber: getLineNumber(for: Syntax(initializer)),
                            suggestion: "Create constants for UI values to improve maintainability",
                            ruleName: currentPattern?.name
                        )
                    }
                } else if let floatLiteral = initializer.value.as(FloatLiteralExprSyntax.self) {
                    if let value = Double(floatLiteral.literal.text), value >= Double(configuration.magicNumberThreshold) {
                        addIssue(
                            severity: .info,
                            message: "Consider extracting magic number \(value) into a named constant",
                            filePath: currentFilePath,
                            lineNumber: getLineNumber(for: Syntax(initializer)),
                            suggestion: "Create constants for UI values to improve maintainability",
                            ruleName: currentPattern?.name
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
                        message: "Consider extracting magic number \(value) into a named constant",
                        filePath: currentFilePath,
                        lineNumber: getLineNumber(for: Syntax(argument)),
                        suggestion: "Create constants for UI values to improve maintainability",
                        ruleName: currentPattern?.name
                    )
                }
            } else if let floatLiteral = argument.expression.as(FloatLiteralExprSyntax.self) {
                if let value = Double(floatLiteral.literal.text), value >= Double(configuration.magicNumberThreshold) {
                    addIssue(
                        severity: .info,
                        message: "Consider extracting magic number \(value) into a named constant",
                        filePath: currentFilePath,
                        lineNumber: getLineNumber(for: Syntax(argument)),
                        suggestion: "Create constants for UI values to improve maintainability",
                        ruleName: currentPattern?.name
                    )
                }
            }
        }
        return .visitChildren
    }
    
    override func visit(_ node: StringLiteralExprSyntax) -> SyntaxVisitorContinueKind {
        // Check for hardcoded strings that should be localized
        // Only consider string literals with a single segment (no interpolation)
        let segments = node.segments
        if segments.count == 1, let segment = segments.first?.as(StringSegmentSyntax.self) {
            let cleanString = segment.content.text
            if cleanString.count >= configuration.minStringLengthForLocalization && !cleanString.contains("\\") {
                let skipPatterns = [
                    "http", "https", "file://", "data:", "base64",
                    "private", "public", "internal", "class", "struct", "enum",
                    "func", "var", "let", "if", "else", "guard", "return"
                ]
                let shouldSkip = skipPatterns.contains { cleanString.contains($0) }
                if !shouldSkip {
                    addIssue(
                        severity: .info,
                        message: "Consider using localized strings instead of hardcoded text: \"\(cleanString)\"",
                        filePath: currentFilePath,
                        lineNumber: getLineNumber(for: Syntax(node)),
                        suggestion: "Move strings to Localizable.strings for internationalization",
                        ruleName: currentPattern?.name
                    )
                }
            }
        }
        return .visitChildren
    }
    
    override func visit(_ node: MemberAccessExprSyntax) -> SyntaxVisitorContinueKind {
        // Track if we're in a view body
        if node.declName.baseName.text == "body" {
            isInViewBody = true
        }
        
        return .visitChildren
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
                message: "Consider adding documentation for '\(name)'",
                filePath: currentFilePath,
                lineNumber: getLineNumber(for: node),
                suggestion: "Add /// documentation comments for public APIs",
                ruleName: currentPattern?.name
            )
        }
    }
}

// MARK: - Code Quality Pattern Extensions

extension CodeQualityVisitor {
    /// Configuration for code quality detection.
    struct Configuration {
        let maxFunctionLength: Int
        let minStringLengthForLocalization: Int
        let magicNumberThreshold: Int
        let checkPublicAPIsOnly: Bool
        
        static let `default` = Configuration(
            maxFunctionLength: 200,
            minStringLengthForLocalization: 10,
            magicNumberThreshold: 10,
            checkPublicAPIsOnly: true
        )
        
        static let strict = Configuration(
            maxFunctionLength: 150,
            minStringLengthForLocalization: 5,
            magicNumberThreshold: 5,
            checkPublicAPIsOnly: false
        )
    }
} 
