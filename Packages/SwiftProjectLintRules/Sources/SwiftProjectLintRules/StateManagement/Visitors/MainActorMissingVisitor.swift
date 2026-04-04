import SwiftProjectLintModels
import SwiftProjectLintRegistry
import SwiftProjectLintVisitors
import SwiftSyntax

/// A cross-file SwiftSyntax visitor that detects `ObservableObject`-conforming classes
/// with `@Published` properties that are missing a `@MainActor` annotation.
///
/// **Why this matters:** In Swift 6 strict concurrency, mutations to `@Published` properties
/// must happen on the main actor — they drive view updates, which are inherently main-thread
/// operations. A class that omits `@MainActor` compiles cleanly but allows off-main-thread
/// mutation of UI state, leading to data races and undefined rendering behaviour.
///
/// **Detection:** Flags any `class` that:
/// 1. Conforms to `ObservableObject` in its inheritance clause.
/// 2. Has at least one `@Published` stored property.
/// 3. Is NOT itself annotated `@MainActor`.
///
/// **Cross-file suppression:** Uses a two-pass approach via `CrossFilePatternVisitorProtocol`.
/// Pass 1 (the walk) collects the names of all explicitly `@MainActor`-annotated classes
/// across every file in the project. Pass 2 (`finalizeAnalysis`) emits issues only for
/// candidates whose superclass is not in that set, suppressing false positives for subclasses
/// that inherit `@MainActor` isolation from a base class defined in another file.
///
/// **Known limitation:** Suppression covers one level of inheritance only (direct superclass).
/// Multi-level chains and base classes from external frameworks or SPM packages are not
/// in the file cache and cannot be suppressed automatically. Teams using
/// `swiftSettings: [.defaultIsolation(MainActor.self)]` in `Package.swift` will see
/// false positives; they should disable this rule for those targets.
final class MainActorMissingVisitor: BasePatternVisitor, CrossFilePatternVisitorProtocol {

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

    /// Candidates to flag: captured at walk time when file/location context is correct.
    private struct Candidate {
        let typeName: String
        let inheritedTypeNames: [String]
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

        // Only flag ObservableObject classes with @Published properties that lack @MainActor.
        guard conformsToObservableObject(node),
              hasPublishedProperties(node),
              !isMainActorAnnotated(node.attributes) else {
            return .visitChildren
        }

        candidates.append(Candidate(
            typeName: typeName,
            inheritedTypeNames: inheritedTypeNames(from: node.inheritanceClause),
            filePath: getFilePath(for: Syntax(node)),
            lineNumber: getLineNumber(for: Syntax(node))
        ))

        return .visitChildren
    }

    // MARK: - Cross-File Finalization

    /// Emits issues for candidates whose direct superclass is not a known `@MainActor` class.
    func finalizeAnalysis() {
        for candidate in candidates {
            let isSuppressed = candidate.inheritedTypeNames.contains {
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

    private func conformsToObservableObject(_ node: ClassDeclSyntax) -> Bool {
        guard let clause = node.inheritanceClause else { return false }
        return clause.inheritedTypes.contains {
            $0.type.as(IdentifierTypeSyntax.self)?.name.text == "ObservableObject"
        }
    }

    private func hasPublishedProperties(_ node: ClassDeclSyntax) -> Bool {
        node.memberBlock.members.contains { member in
            guard let varDecl = member.decl.as(VariableDeclSyntax.self) else { return false }
            return varDecl.attributes.contains { element in
                element.as(AttributeSyntax.self)?.attributeName.trimmedDescription == "Published"
            }
        }
    }

    private func inheritedTypeNames(from clause: InheritanceClauseSyntax?) -> [String] {
        guard let clause else { return [] }
        return clause.inheritedTypes.compactMap {
            $0.type.as(IdentifierTypeSyntax.self)?.name.text
        }
    }
}
