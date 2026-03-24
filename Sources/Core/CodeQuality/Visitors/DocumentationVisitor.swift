import Foundation
import SwiftSyntax

/// A SwiftSyntax visitor that detects missing documentation comments.
///
/// By default only flags public APIs. Set `configuration` to `.strict` to
/// also flag internal/private declarations.
class DocumentationVisitor: BasePatternVisitor {
    private var currentFunctionName: String = ""
    private var currentStructName: String = ""
    private var currentFilePath: String = ""
    private var configuration: Configuration

    required init(pattern: SyntaxPattern, viewMode: SyntaxTreeViewMode = .sourceAccurate) {
        self.configuration = .default
        super.init(pattern: pattern, viewMode: viewMode)
    }

    convenience init(patternCategory: PatternCategory, configuration: Configuration = .default, viewMode: SyntaxTreeViewMode = .sourceAccurate) {
        let placeholder = SyntaxPattern(
            name: .unknown,
            visitor: DocumentationVisitor.self,
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

    // MARK: - Visits

    override func visit(_ node: StructDeclSyntax) -> SyntaxVisitorContinueKind {
        currentStructName = node.name.text
        if node.modifiers.contains(where: { $0.name.text == "public" }) {
            checkMissingDocumentation(for: Syntax(node), name: currentStructName)
        }
        return .visitChildren
    }

    override func visit(_ node: ClassDeclSyntax) -> SyntaxVisitorContinueKind {
        currentStructName = node.name.text
        if node.modifiers.contains(where: { $0.name.text == "public" }) {
            checkMissingDocumentation(for: Syntax(node), name: currentStructName)
        }
        return .visitChildren
    }

    override func visit(_ node: FunctionDeclSyntax) -> SyntaxVisitorContinueKind {
        currentFunctionName = node.name.text
        if configuration.checkPublicAPIsOnly {
            let isPublic = node.modifiers.contains { $0.name.text == "public" }
            if isPublic {
                checkMissingDocumentation(for: Syntax(node), name: currentFunctionName)
            }
        } else {
            checkMissingDocumentation(for: Syntax(node), name: currentFunctionName)
        }
        return .visitChildren
    }

    // MARK: - Private helpers

    private func checkMissingDocumentation(for node: Syntax, name: String) {
        let hasDocumentation = node.leadingTrivia.contains { piece in
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

extension DocumentationVisitor {
    struct Configuration {
        let checkPublicAPIsOnly: Bool

        // swiftprojectlint:disable:this could-be-private-member
        static let `default` = Configuration(checkPublicAPIsOnly: true)
        // swiftprojectlint:disable:this could-be-private-member
        static let strict = Configuration(checkPublicAPIsOnly: false)
    }
}
