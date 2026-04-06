import SwiftProjectLintModels
import SwiftProjectLintRegistry
import SwiftProjectLintVisitors
import SwiftSyntax

/// A cross-file SwiftSyntax visitor that detects `@Observable` classes that are not
/// annotated `@MainActor`.
///
/// **Why this matters:** The `@Observable` macro (Swift 5.9 / iOS 17+) synthesises
/// observation infrastructure for every stored property in the class.  Those properties
/// drive SwiftUI view updates, which are inherently main-thread operations.  Without
/// `@MainActor`, any code — including background `Task`s — can mutate observed state
/// off the main thread, producing data races and undefined rendering behaviour under
/// Swift 6 strict concurrency.
///
/// **Detection:** Flags any `class` declaration that:
/// 1. Has an `@Observable` attribute.
/// 2. Is NOT itself annotated `@MainActor`.
///
/// **Cross-file suppression:** Uses a two-pass approach via `CrossFilePatternVisitorProtocol`.
/// Pass 1 (the walk) collects all explicitly `@MainActor`-annotated class names across every
/// file in the project.  Pass 2 (`finalizeAnalysis`) suppresses candidates whose direct
/// superclass is in that set — the subclass inherits main-actor isolation automatically.
///
/// **Known limitation:** Suppression covers one level of inheritance only.  Multi-level
/// chains and classes from external frameworks or SPM packages are not in the file cache.
/// Teams using `swiftSettings: [.defaultIsolation(MainActor.self)]` in `Package.swift`
/// will see false positives; they should disable this rule for those targets.
final class ObservableMainActorMissingVisitor: BasePatternVisitor, CrossFilePatternVisitorProtocol {

    // MARK: - CrossFilePatternVisitorProtocol

    let fileCache: [String: SourceFileSyntax]

    required init(fileCache: [String: SourceFileSyntax]) {
        self.fileCache = fileCache
        super.init(pattern: BasePatternVisitor.placeholderPattern)
    }

    required init(pattern: SyntaxPattern, viewMode: SyntaxTreeViewMode = .sourceAccurate) {
        self.fileCache = [:]
        super.init(pattern: pattern, viewMode: viewMode)
    }

    // MARK: - State

    /// All class names explicitly annotated `@MainActor`, collected across all files.
    private var mainActorClassNames: Set<String> = []

    private struct Candidate {
        let typeName: String
        let superclassNames: [String]
        let filePath: String
        let lineNumber: Int
    }
    private var candidates: [Candidate] = []

    // MARK: - Visitor

    override func visit(_ node: ClassDeclSyntax) -> SyntaxVisitorContinueKind {
        let typeName = node.name.text

        // Pass 1: collect @MainActor class names for cross-file suppression.
        if isMainActorAnnotated(node.attributes) {
            mainActorClassNames.insert(typeName)
        }

        guard isObservableAnnotated(node.attributes),
              !isMainActorAnnotated(node.attributes) else {
            return .visitChildren
        }

        candidates.append(Candidate(
            typeName: typeName,
            superclassNames: inheritedTypeNames(from: node.inheritanceClause),
            filePath: getFilePath(for: Syntax(node)),
            lineNumber: getLineNumber(for: Syntax(node))
        ))

        return .visitChildren
    }

    // MARK: - Cross-File Finalization

    func finalizeAnalysis() {
        for candidate in candidates {
            let isSuppressed = candidate.superclassNames.contains {
                mainActorClassNames.contains($0)
            }
            guard !isSuppressed else { continue }

            let message = pattern.messageTemplate
                .replacingOccurrences(of: "{typeName}", with: candidate.typeName)
            addIssue(
                severity: pattern.severity,
                message: message,
                filePath: candidate.filePath,
                lineNumber: candidate.lineNumber,
                suggestion: pattern.suggestion,
                ruleName: pattern.name
            )
        }
    }

    // MARK: - Helpers

    private func isMainActorAnnotated(_ attributes: AttributeListSyntax) -> Bool {
        attributes.contains { element in
            element.as(AttributeSyntax.self)?.attributeName.trimmedDescription == "MainActor"
        }
    }

    private func isObservableAnnotated(_ attributes: AttributeListSyntax) -> Bool {
        attributes.contains { element in
            element.as(AttributeSyntax.self)?.attributeName.trimmedDescription == "Observable"
        }
    }

    private func inheritedTypeNames(from clause: InheritanceClauseSyntax?) -> [String] {
        guard let clause else { return [] }
        return clause.inheritedTypes.compactMap {
            $0.type.as(IdentifierTypeSyntax.self)?.name.text
        }
    }
}
