import Foundation
import SwiftProjectLintVisitors
import SwiftSyntax

/// Shared base for the two "missing `@MainActor`" cross-file rules.
///
/// Both rules flag a `class` that should be main-actor-isolated but isn't, and
/// both share the same machinery: a Pass-1 walk that collects every explicitly
/// `@MainActor`-annotated class name for cross-file suppression and captures
/// candidates, and a Pass-2 `finalizeAnalysis` that emits unless a candidate's
/// direct superclass is a known `@MainActor` class (so subclasses inheriting
/// isolation from a base class in another file aren't flagged).
///
/// The only difference is *which* classes are candidates — subclasses override
/// ``isCandidate(_:)``. The base applies the `@MainActor`-absence check itself.
class MainActorMissingVisitorBase: CrossFileVisitorBase, CrossFilePatternVisitorProtocol {

    /// All class names explicitly annotated `@MainActor`, collected across all files.
    private var mainActorClassNames: Set<String> = []

    private struct Candidate {
        let typeName: String
        let inheritedTypeNames: [String]
        let filePath: String
        let lineNumber: Int
    }
    private var candidates: [Candidate] = []

    /// Whether the class is one this rule should flag when it lacks `@MainActor`.
    /// Subclasses override with the positive predicate only — the base applies the
    /// `@MainActor`-absence check.
    func isCandidate(_: ClassDeclSyntax) -> Bool { false }

    // MARK: - Pass 1: walk

    override func visit(_ node: ClassDeclSyntax) -> SyntaxVisitorContinueKind {
        let typeName = node.name.text

        // Collect @MainActor class names for cross-file suppression.
        if hasAttribute(node.attributes, named: "MainActor") {
            mainActorClassNames.insert(typeName)
        }

        guard isCandidate(node),
              !hasAttribute(node.attributes, named: "MainActor") else {
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

    // MARK: - Pass 2: finalize

    /// Emits issues for candidates whose direct superclass is not a known
    /// `@MainActor` class.
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

    /// Whether `attributes` contains an attribute named `name`
    /// (e.g. `@MainActor`, `@Observable`, `@Published`).
    func hasAttribute(_ attributes: AttributeListSyntax, named name: String) -> Bool {
        attributes.contains { element in
            element.as(AttributeSyntax.self)?.attributeName.trimmedDescription == name
        }
    }

    private func inheritedTypeNames(from clause: InheritanceClauseSyntax?) -> [String] {
        guard let clause else { return [] }
        return clause.inheritedTypes.compactMap {
            $0.type.as(IdentifierTypeSyntax.self)?.name.text
        }
    }
}
