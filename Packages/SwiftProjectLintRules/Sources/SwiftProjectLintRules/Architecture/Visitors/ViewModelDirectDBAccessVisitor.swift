import SwiftProjectLintModels
import SwiftProjectLintRegistry
import SwiftProjectLintVisitors
import SwiftSyntax

/// Detects view models that directly import persistence frameworks.
///
/// Direct database access in view models violates separation of concerns,
/// makes them hard to test, and couples business logic to storage
/// implementation. Opt-in rule — many small apps intentionally use
/// `@Query` directly per Apple's SwiftData tutorials.
final class ViewModelDirectDBAccessVisitor: BasePatternVisitor {
    private var currentFilePath: String = ""

    private static let persistenceFrameworks: Set<String> = [
        "CoreData", "SwiftData", "RealmSwift", "GRDB", "SQLite"
    ]

    private static let repositorySuffixes: [String] = [
        "Repository", "Store", "Service", "DataSource", "DAO",
        "Persistence", "Storage", "Provider"
    ]

    /// Imported persistence frameworks found in this file.
    private var importedFrameworks: [String] = []

    /// Whether this file contains a view model class.
    private var viewModelClassNames: [String] = []

    required init(pattern: SyntaxPattern, viewMode: SyntaxTreeViewMode = .sourceAccurate) {
        super.init(pattern: pattern, viewMode: viewMode)
    }

    override func setFilePath(_ filePath: String) {
        self.currentFilePath = filePath
        importedFrameworks = []
        viewModelClassNames = []
    }

    // MARK: - Track imports

    override func visit(_ node: ImportDeclSyntax) -> SyntaxVisitorContinueKind {
        let moduleName = node.path.map { $0.name.text }.joined(separator: ".")
        if Self.persistenceFrameworks.contains(moduleName) {
            importedFrameworks.append(moduleName)
        }
        return .visitChildren
    }

    // MARK: - Detect view model classes

    override func visit(_ node: ClassDeclSyntax) -> SyntaxVisitorContinueKind {
        let className = node.name.text

        // Suppress if this looks like a repository/service layer
        if isRepositoryClass(className) || isRepositoryFile() {
            return .visitChildren
        }

        let isViewModel = isViewModelClass(node, name: className)
        guard isViewModel, importedFrameworks.isEmpty == false else {
            return .visitChildren
        }

        for framework in importedFrameworks {
            addIssue(
                severity: .info,
                message: "View model '\(className)' directly imports "
                    + "'\(framework)' — consider using a repository/service layer",
                filePath: currentFilePath,
                lineNumber: getLineNumber(for: Syntax(node)),
                suggestion: "Extract persistence logic into a repository or "
                    + "service class for better testability and separation.",
                ruleName: .viewModelDirectDBAccess
            )
        }

        return .visitChildren
    }

    // MARK: - Helpers

    private func isViewModelClass(_ node: ClassDeclSyntax, name: String) -> Bool {
        // Name-based: ends in ViewModel or VM
        if name.hasSuffix("ViewModel") || name.hasSuffix("VM") {
            return true
        }

        // Conformance-based: ObservableObject
        if let inheritance = node.inheritanceClause {
            let conformances = inheritance.inheritedTypes.map {
                $0.type.trimmedDescription
            }
            if conformances.contains("ObservableObject") {
                return true
            }
        }

        // Attribute-based: @Observable
        let hasObservable = node.attributes.contains { attr in
            guard let attrSyntax = attr.as(AttributeSyntax.self) else { return false }
            return attrSyntax.attributeName.trimmedDescription == "Observable"
        }
        return hasObservable
    }

    private func isRepositoryClass(_ name: String) -> Bool {
        Self.repositorySuffixes.contains { name.contains($0) }
    }

    private func isRepositoryFile() -> Bool {
        let fileName = currentFilePath.split(separator: "/").last
            .map(String.init) ?? currentFilePath
        return Self.repositorySuffixes.contains { fileName.contains($0) }
    }
}
