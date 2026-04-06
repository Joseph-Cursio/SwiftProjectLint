import SwiftProjectLintModels
import SwiftProjectLintRegistry
import SwiftProjectLintVisitors
import SwiftSyntax

/// Detects `ObservableObject` classes and assesses readiness for migration to
/// the `@Observable` macro (iOS 17+).
///
/// Provides a readiness score:
/// - **High**: Only uses `@Published`, no manual `objectWillChange`, no Combine usage.
/// - **Medium**: Uses `objectWillChange.send()` manually (needs removal).
/// - **Low**: Uses Combine publisher features (`$property`, `objectWillChange` downstream).
///
/// Opt-in companion to the simpler `legacyObservableObject` rule.
final class IOS17ObservationMigrationVisitor: BasePatternVisitor {

    required init(pattern: SyntaxPattern, viewMode: SyntaxTreeViewMode = .sourceAccurate) {
        super.init(pattern: pattern, viewMode: viewMode)
    }

    override func visit(_ node: ClassDeclSyntax) -> SyntaxVisitorContinueKind {
        guard conformsToObservableObject(node) else { return .visitChildren }

        // Suppress: NSObject subclass (can't use @Observable)
        if inheritsFromNSObject(node) { return .visitChildren }

        let className = node.name.text
        let memberBlock = node.memberBlock

        // Analyze readiness
        let usesCombinePublishers = detectsCombinePublisherUsage(memberBlock)
        let usesManualObjectWillChange = detectsManualObjectWillChange(memberBlock)
        let publishedCount = countPublishedProperties(memberBlock)

        // Suppress if using Combine publisher features
        if usesCombinePublishers { return .visitChildren }

        let readiness: String
        if usesManualObjectWillChange {
            readiness = "medium"
        } else if publishedCount > 0 {
            readiness = "high"
        } else {
            readiness = "low"
        }

        addIssue(
            severity: .info,
            message: "'\(className)' could migrate to @Observable "
                + "(readiness: \(readiness)) — improved performance "
                + "with granular tracking",
            filePath: getFilePath(for: Syntax(node)),
            lineNumber: getLineNumber(for: Syntax(node)),
            suggestion: "Replace ObservableObject with @Observable, remove "
                + "@Published wrappers, update @ObservedObject to plain properties.",
            ruleName: .ios17ObservationMigration
        )
        return .visitChildren
    }

    // MARK: - Helpers

    private func conformsToObservableObject(_ node: ClassDeclSyntax) -> Bool {
        node.inheritanceClause?.inheritedTypes.contains { inherited in
            inherited.type.trimmedDescription == "ObservableObject"
        } ?? false
    }

    private func inheritsFromNSObject(_ node: ClassDeclSyntax) -> Bool {
        node.inheritanceClause?.inheritedTypes.contains { inherited in
            inherited.type.trimmedDescription == "NSObject"
        } ?? false
    }

    private func countPublishedProperties(_ memberBlock: MemberBlockSyntax) -> Int {
        var count = 0
        for member in memberBlock.members {
            guard let varDecl = member.decl.as(VariableDeclSyntax.self) else { continue }
            let hasPublished = varDecl.attributes.contains { attr in
                guard let attrSyntax = attr.as(AttributeSyntax.self) else { return false }
                return attrSyntax.attributeName.trimmedDescription == "Published"
            }
            if hasPublished { count += 1 }
        }
        return count
    }

    /// Detects `objectWillChange.send()` calls inside the class body.
    private func detectsManualObjectWillChange(
        _ memberBlock: MemberBlockSyntax
    ) -> Bool {
        let finder = PatternFinder(pattern: "objectWillChange")
        finder.walk(memberBlock)
        return finder.found
    }

    /// Detects Combine publisher usage: `$property` (projected value) references
    /// or `objectWillChange` used as a publisher (chained with Combine operators).
    private func detectsCombinePublisherUsage(
        _ memberBlock: MemberBlockSyntax
    ) -> Bool {
        let finder = CombineUsageFinder()
        finder.walk(memberBlock)
        return finder.found
    }

    // MARK: - Nested finders

    private final class PatternFinder: SyntaxVisitor {
        let pattern: String
        var found = false

        init(pattern: String) {
            self.pattern = pattern
            super.init(viewMode: .sourceAccurate)
        }

        override func visit(_ node: MemberAccessExprSyntax) -> SyntaxVisitorContinueKind {
            if node.declName.baseName.text == pattern {
                found = true
            }
            // Also check base: objectWillChange.send() has "objectWillChange" as base
            if let base = node.base?.as(DeclReferenceExprSyntax.self),
               base.baseName.text == pattern {
                found = true
            }
            return .visitChildren
        }
    }

    private final class CombineUsageFinder: SyntaxVisitor {
        var found = false

        init() { super.init(viewMode: .sourceAccurate) }

        override func visit(_ node: MemberAccessExprSyntax) -> SyntaxVisitorContinueKind {
            // Detect $property (projected value) usage
            if let base = node.base,
               base.trimmedDescription.hasPrefix("$") {
                found = true
            }
            // Detect objectWillChange chained with Combine operators
            if node.declName.baseName.text == "sink"
                || node.declName.baseName.text == "assign"
                || node.declName.baseName.text == "receive" {
                if let innerAccess = node.base?.as(FunctionCallExprSyntax.self),
                   innerAccess.trimmedDescription.contains("objectWillChange") {
                    found = true
                }
            }
            return .visitChildren
        }

        override func visit(_ node: DeclReferenceExprSyntax) -> SyntaxVisitorContinueKind {
            // Detect $property standalone references
            if node.baseName.text.hasPrefix("$") {
                found = true
            }
            return .visitChildren
        }
    }
}
