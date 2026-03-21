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
    private var currentStructName: String = ""
    private var currentFilePath: String = ""
    private var configuration: Configuration

    /// Collects magic number occurrences during the walk.
    /// Only numbers that appear 2+ times are reported (single-use literals are not magic).
    private var magicNumberOccurrences: [String: [(line: Int, message: String, suggestion: String)]] = [:]

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

    override func visit(_ node: VariableDeclSyntax) -> SyntaxVisitorContinueKind {
        for binding in node.bindings {
            if let initializer = binding.initializer {
                if let intLiteral = initializer.value.as(IntegerLiteralExprSyntax.self) {
                    recordMagicNumber(intLiteral.literal.text, node: Syntax(initializer))
                } else if let floatLiteral = initializer.value.as(FloatLiteralExprSyntax.self) {
                    recordMagicNumber(floatLiteral.literal.text, node: Syntax(initializer))
                }
            }
        }
        return .visitChildren
    }

    override func visit(_ node: FunctionCallExprSyntax) -> SyntaxVisitorContinueKind {
        for argument in node.arguments {
            if let intLiteral = argument.expression.as(IntegerLiteralExprSyntax.self) {
                recordMagicNumber(intLiteral.literal.text, node: Syntax(argument))
            } else if let floatLiteral = argument.expression.as(FloatLiteralExprSyntax.self) {
                recordMagicNumber(floatLiteral.literal.text, node: Syntax(argument))
            }
        }
        return .visitChildren
    }

    /// Records a numeric literal for later duplicate checking.
    private func recordMagicNumber(_ literal: String, node: Syntax) {
        let numericValue: Double
        if let intVal = Int(literal) {
            guard intVal >= configuration.magicNumberThreshold else { return }
            numericValue = Double(intVal)
        } else if let dblVal = Double(literal) {
            guard dblVal >= Double(configuration.magicNumberThreshold) else { return }
            numericValue = dblVal
        } else {
            return
        }
        let key = literal
        let entry = (
            line: getLineNumber(for: node),
            message: "Consider extracting magic number \(literal) to a named constant",
            suggestion: "Extract \(literal) to a named constant for better maintainability"
        )
        magicNumberOccurrences[key, default: []].append(entry)
    }

    /// Reports magic numbers that appear more than once in the file.
    override func visitPost(_ node: SourceFileSyntax) {
        for (_, occurrences) in magicNumberOccurrences where occurrences.count >= 2 {
            for occurrence in occurrences {
                addIssue(
                    severity: .info,
                    message: occurrence.message,
                    filePath: currentFilePath,
                    lineNumber: occurrence.line,
                    suggestion: occurrence.suggestion,
                    ruleName: .magicNumber
                )
            }
        }
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
            || looksLikeSFSymbolName(cleanString)
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

    /// Argument labels that take SF Symbol names or other non-localizable identifiers.
    private static let nonLocalizableArgLabels: Set<String> = [
        "systemImage", "systemName", "imageName", "symbolName"
    ]

    /// Checks whether a string literal is a direct argument to a user-facing SwiftUI call.
    private func isInUserFacingContext(_ node: StringLiteralExprSyntax) -> Bool {
        // Walk up to the nearest FunctionCallExprSyntax ancestor
        var current: Syntax = Syntax(node)
        while let parent = current.parent {
            // Skip strings that are SF Symbol names or other non-localizable arguments
            if let labeledArg = parent.as(LabeledExprSyntax.self),
               let argLabel = labeledArg.label?.text,
               Self.nonLocalizableArgLabels.contains(argLabel) {
                return false
            }

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

    /// Known SF Symbol name components that appear as dot-separated segments.
    /// A string is considered an SF Symbol name if it contains at least one dot
    /// and every segment matches a known symbol component pattern.
    private static let sfSymbolModifiers: Set<String> = [
        "fill", "circle", "square", "rectangle", "slash", "badge",
        "trianglebadge", "shield", "seal", "app", "bubble", "plus",
        "minus", "exclamationmark", "questionmark", "lock", "wave",
        "rtl", "ar", "he", "hi", "ja", "ko", "th", "zh"
    ]

    /// Checks whether a string looks like an SF Symbol name.
    /// SF Symbols use dot-separated lowercase components like "checkmark.circle.fill",
    /// "arrow.uturn.backward", "1.circle.fill", etc.
    private func looksLikeSFSymbolName(_ string: String) -> Bool {
        guard string.contains("."),
              !string.contains(" "),
              !string.hasPrefix("."),
              !string.hasSuffix(".") else {
            return false
        }
        let parts = string.split(separator: ".")
        guard parts.count >= 2 else { return false }
        // Every segment must be lowercase alphanumeric (no uppercase = not a sentence)
        return parts.allSatisfy { part in
            !part.isEmpty && part.allSatisfy { $0.isLowercase || $0.isNumber }
        }
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
        let magicNumberThreshold: Int
        let checkPublicAPIsOnly: Bool

        static let `default` = Configuration(
            magicNumberThreshold: 10,
            checkPublicAPIsOnly: true
        )

        static let strict = Configuration(
            magicNumberThreshold: 5,
            checkPublicAPIsOnly: false
        )
    }
}
