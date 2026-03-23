import Foundation
import SwiftSyntax

/// A SwiftSyntax visitor that detects hardcoded strings that should be localized.
///
/// Only flags string literals that appear as direct arguments to user-facing SwiftUI
/// calls (Text, Button, Label, navigationTitle, alert, etc.). URLs, SF Symbol names,
/// and non-localizable argument labels (systemImage, systemName) are skipped.
class HardcodedStringVisitor: BasePatternVisitor {
    private var currentFilePath: String = ""

    required init(pattern: SyntaxPattern, viewMode: SyntaxTreeViewMode = .sourceAccurate) {
        super.init(pattern: pattern, viewMode: viewMode)
    }

    convenience init(patternCategory: PatternCategory, viewMode: SyntaxTreeViewMode = .sourceAccurate) {
        let placeholder = SyntaxPattern(
            name: .unknown,
            visitor: HardcodedStringVisitor.self,
            severity: .warning,
            category: patternCategory,
            messageTemplate: "",
            suggestion: "",
            description: ""
        )
        self.init(pattern: placeholder, viewMode: viewMode)
    }

    override func setFilePath(_ filePath: String) {
        self.currentFilePath = filePath
    }

    // MARK: - Sets

    /// SwiftUI initializers and modifiers whose string arguments are shown to users.
    private static let userFacingCallNames: Set<String> = [
        "Text", "Label", "Button", "Toggle", "Picker", "Slider",
        "Section", "NavigationLink", "TabItem", "DisclosureGroup",
        "navigationTitle", "navigationBarTitle",
        "alert", "confirmationDialog",
        "headerProminence", "badge",
        "help", "toolbarItem"
    ]

    /// Argument labels that take SF Symbol names or other non-localizable identifiers.
    private static let nonLocalizableArgLabels: Set<String> = [
        "systemImage", "systemName", "imageName", "symbolName"
    ]

    // MARK: - Visit

    override func visit(_ node: StringLiteralExprSyntax) -> SyntaxVisitorContinueKind {
        let segments = node.segments
        guard segments.count == 1,
              let segment = segments.first?.as(StringSegmentSyntax.self) else {
            return .visitChildren
        }
        let cleanString = segment.content.text
        guard !cleanString.isEmpty,
              !cleanString.contains("\\"),
              cleanString.count > 2,
              !isTestFile(),
              isInUserFacingContext(node) else {
            return .visitChildren
        }

        let skipPatterns = ["http", "https", "file://", "data:", "base64"]
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

    // MARK: - Private helpers

    private func isInUserFacingContext(_ node: StringLiteralExprSyntax) -> Bool {
        var current: Syntax = Syntax(node)
        while let parent = current.parent {
            if let labeledArg = parent.as(LabeledExprSyntax.self),
               let argLabel = labeledArg.label?.text,
               Self.nonLocalizableArgLabels.contains(argLabel) {
                return false
            }
            if let call = parent.as(FunctionCallExprSyntax.self) {
                if let ref = call.calledExpression.as(DeclReferenceExprSyntax.self),
                   Self.userFacingCallNames.contains(ref.baseName.text) {
                    return true
                }
                if let member = call.calledExpression.as(MemberAccessExprSyntax.self),
                   Self.userFacingCallNames.contains(member.declName.baseName.text) {
                    return true
                }
            }
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

    private func isTestFile() -> Bool {
        currentFilePath.contains("Tests") || currentFilePath.hasSuffix("Tests.swift")
    }

    private func looksLikeSFSymbolName(_ string: String) -> Bool {
        guard string.contains("."),
              !string.contains(" "),
              !string.hasPrefix("."),
              !string.hasSuffix(".") else {
            return false
        }
        let parts = string.split(separator: ".")
        guard parts.count >= 2 else { return false }
        return parts.allSatisfy { part in
            !part.isEmpty && part.allSatisfy { $0.isLowercase || $0.isNumber }
        }
    }
}
