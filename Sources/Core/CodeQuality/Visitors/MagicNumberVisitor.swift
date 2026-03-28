import Foundation
import SwiftSyntax

/// A SwiftSyntax visitor that detects magic numbers in Swift code.
///
/// Reports numeric literals that appear 2+ times in a file without being
/// assigned to a named constant. Single-use literals are not flagged.
/// Layout/geometry modifiers (padding, frame, cornerRadius, etc.) are
/// tracked separately under the opt-in `.magicLayoutNumber` rule.
class MagicNumberVisitor: BasePatternVisitor {
    private var currentFilePath: String = ""
    private var configuration: Configuration

    /// Collects magic number occurrences during the walk.
    /// Only numbers that appear 2+ times are reported (single-use literals are not magic).
    private var magicNumberOccurrences: [String: [(line: Int, message: String, suggestion: String)]] = [:]

    /// Collects layout magic number occurrences (reported under the opt-in layout rule).
    private var layoutNumberOccurrences: [String: [(line: Int, message: String, suggestion: String)]] = [:]

    required init(pattern: SyntaxPattern, viewMode: SyntaxTreeViewMode = .sourceAccurate) {
        self.configuration = .default
        super.init(pattern: pattern, viewMode: viewMode)
    }

    convenience init(patternCategory: PatternCategory, configuration: Configuration = .default, viewMode: SyntaxTreeViewMode = .sourceAccurate) {
        let placeholder = SyntaxPattern(
            name: .unknown,
            visitor: MagicNumberVisitor.self,
            severity: .warning,
            category: patternCategory,
            messageTemplate: "",
            suggestion: "",
            description: ""
        )
        self.init(pattern: placeholder, viewMode: viewMode)
        self.configuration = configuration
    }

    override func setFilePath(_ filePath: String) {
        self.currentFilePath = filePath
    }

    // MARK: - SwiftUI layout/geometry sets

    /// SwiftUI layout/geometry modifiers and constructors where numeric literals
    /// are conventional design tokens, not magic numbers.
    private static let layoutModifierNames: Set<String> = [
        "padding", "spacing",
        "frame", "fixedSize", "lineLimit", "lineSpacing",
        "cornerRadius", "rotation", "rotationEffect",
        "scaleEffect", "offset", "shadow",
        "opacity", "blur",
        "gridCellColumns", "columns",
        "font", "system",
        "GridItem", "Spacer", "Divider",
        "RoundedRectangle", "Circle", "Capsule",
        "UnevenRoundedRectangle"
    ]

    /// Labeled arguments that are layout/geometry values, regardless of the function name.
    private static let layoutArgLabels: Set<String> = [
        "width", "height", "minWidth", "maxWidth", "minHeight", "maxHeight",
        "idealWidth", "idealHeight",
        "horizontal", "vertical", "top", "bottom", "leading", "trailing",
        "minimum", "maximum", "spacing", "radius", "lineWidth",
        "size", "weight", "min", "ideal", "max"
    ]

    /// Function name prefixes where numeric arguments are positional indices, not magic numbers.
    private static let positionalIndexPrefixes: [String] = [
        "sqlite3_bind_"
    ]

    // MARK: - Visits

    override func visit(_ node: VariableDeclSyntax) -> SyntaxVisitorContinueKind {
        if isInsidePreviewMacro(Syntax(node)) { return .visitChildren }
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
        if isInsidePreviewMacro(Syntax(node)) { return .visitChildren }

        let calledName: String?
        if let memberAccess = node.calledExpression.as(MemberAccessExprSyntax.self) {
            calledName = memberAccess.declName.baseName.text
        } else if let declRef = node.calledExpression.as(DeclReferenceExprSyntax.self) {
            calledName = declRef.baseName.text
        } else {
            calledName = nil
        }

        let isLayoutCall = calledName.map { Self.layoutModifierNames.contains($0) } ?? false
        let isPositionalCall = calledName.map { name in
            Self.positionalIndexPrefixes.contains { name.hasPrefix($0) }
        } ?? false

        guard !isPositionalCall else { return .visitChildren }

        for argument in node.arguments {
            let isLayoutArg = isLayoutCall || (
                argument.label.map { Self.layoutArgLabels.contains($0.text) } ?? false
            )
            if let intLiteral = argument.expression.as(IntegerLiteralExprSyntax.self) {
                if isLayoutArg {
                    recordLayoutNumber(intLiteral.literal.text, node: Syntax(argument))
                } else {
                    recordMagicNumber(intLiteral.literal.text, node: Syntax(argument))
                }
            } else if let floatLiteral = argument.expression.as(FloatLiteralExprSyntax.self) {
                if isLayoutArg {
                    recordLayoutNumber(floatLiteral.literal.text, node: Syntax(argument))
                } else {
                    recordMagicNumber(floatLiteral.literal.text, node: Syntax(argument))
                }
            }
        }
        return .visitChildren
    }

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
        for (_, occurrences) in layoutNumberOccurrences where occurrences.count >= 2 {
            for occurrence in occurrences {
                addIssue(
                    severity: .info,
                    message: occurrence.message,
                    filePath: currentFilePath,
                    lineNumber: occurrence.line,
                    suggestion: occurrence.suggestion,
                    ruleName: .magicLayoutNumber
                )
            }
        }
    }

    // MARK: - Private helpers

    private func isInsidePreviewMacro(_ node: Syntax) -> Bool {
        var current: Syntax? = node
        while let ancestor = current {
            if let macro = ancestor.as(MacroExpansionExprSyntax.self),
               macro.macroName.text == "Preview" {
                return true
            }
            current = ancestor.parent
        }
        return false
    }

    private func recordMagicNumber(_ literal: String, node: Syntax) {
        if let intVal = Int(literal) {
            guard intVal >= configuration.magicNumberThreshold else { return }
        } else if let dblVal = Double(literal) {
            guard dblVal >= Double(configuration.magicNumberThreshold) else { return }
        } else {
            return
        }
        let entry = (
            line: getLineNumber(for: node),
            message: "Consider extracting magic number \(literal) to a named constant",
            suggestion: "Extract \(literal) to a named constant for better maintainability"
        )
        magicNumberOccurrences[literal, default: []].append(entry)
    }

    private func recordLayoutNumber(_ literal: String, node: Syntax) {
        if let intVal = Int(literal) {
            guard intVal >= configuration.magicNumberThreshold else { return }
        } else if let dblVal = Double(literal) {
            guard dblVal >= Double(configuration.magicNumberThreshold) else { return }
        } else {
            return
        }
        let entry = (
            line: getLineNumber(for: node),
            message: "Consider extracting layout value \(literal) to a named constant",
            suggestion: "Extract \(literal) to a design token (e.g., Spacing.medium, Layout.cornerRadius)"
        )
        layoutNumberOccurrences[literal, default: []].append(entry)
    }
}

extension MagicNumberVisitor {
    struct Configuration {
        let magicNumberThreshold: Int

        // swiftprojectlint:disable:this could-be-private-member
        static let `default` = Configuration(magicNumberThreshold: 10)
        // swiftprojectlint:disable:this could-be-private-member
        static let strict = Configuration(magicNumberThreshold: 5)
    }
}
