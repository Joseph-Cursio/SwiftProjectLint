import SwiftSyntax

/// A cross-file visitor that detects top-level types with internal (default) access
/// that are only referenced in their declaring file and could be narrowed to `private`.
///
/// **Phase 1 (walk):** Collects all top-level type declarations and all type references
/// across every file.
/// **Phase 2 (finalizeAnalysis):** Compares declarations against references. Types that
/// are never referenced outside their declaring file are flagged.
final class CouldBePrivateVisitor: BasePatternVisitor, CrossFilePatternVisitorProtocol {
    let fileCache: [String: SourceFileSyntax]

    /// Tracks where each type name is declared: typeName → fileName
    private var declarations: [(name: String, file: String, node: Syntax)] = []

    /// Tracks which files reference each type name: typeName → Set<fileName>
    private var references: [String: Set<String>] = [:]

    /// The file currently being walked.
    private var currentFile: String = ""

    /// All declared type names (to avoid flagging references to external types).
    private var declaredTypeNames: Set<String> = []

    required init(fileCache: [String: SourceFileSyntax]) {
        self.fileCache = fileCache
        super.init(pattern: BasePatternVisitor.placeholderPattern, viewMode: .sourceAccurate)
    }

    required init(pattern: SyntaxPattern, viewMode: SyntaxTreeViewMode = .sourceAccurate) {
        self.fileCache = [:]
        super.init(pattern: pattern, viewMode: viewMode)
    }

    // MARK: - File Walking

    override func setFilePath(_ filePath: String) {
        super.setFilePath(filePath)
        currentFile = filePath
    }

    // MARK: - Collect Declarations (top-level, internal access only)

    override func visit(_ node: StructDeclSyntax) -> SyntaxVisitorContinueKind {
        // Skip App entry points and @main types — they can't be private
        guard !isSwiftUIApp(node), !hasMainAttribute(node.attributes) else { return .visitChildren }
        collectDeclarationIfEligible(node.name.text, modifiers: node.modifiers, node: Syntax(node))
        return .visitChildren
    }

    override func visit(_ node: ClassDeclSyntax) -> SyntaxVisitorContinueKind {
        collectDeclarationIfEligible(node.name.text, modifiers: node.modifiers, node: Syntax(node))
        return .visitChildren
    }

    override func visit(_ node: EnumDeclSyntax) -> SyntaxVisitorContinueKind {
        collectDeclarationIfEligible(node.name.text, modifiers: node.modifiers, node: Syntax(node))
        return .visitChildren
    }

    override func visit(_ node: ActorDeclSyntax) -> SyntaxVisitorContinueKind {
        collectDeclarationIfEligible(node.name.text, modifiers: node.modifiers, node: Syntax(node))
        return .visitChildren
    }

    // MARK: - Collect References

    override func visit(_ node: IdentifierTypeSyntax) -> SyntaxVisitorContinueKind {
        references[node.name.text, default: []].insert(currentFile)
        return .visitChildren
    }

    override func visit(_ node: DeclReferenceExprSyntax) -> SyntaxVisitorContinueKind {
        let name = node.baseName.text
        // Only track references that start with uppercase (type names)
        if let first = name.first, first.isUppercase {
            references[name, default: []].insert(currentFile)
        }
        return .visitChildren
    }

    override func visit(_ node: MemberAccessExprSyntax) -> SyntaxVisitorContinueKind {
        // Track Type.member patterns (e.g., Severity.error)
        if let base = node.base?.as(DeclReferenceExprSyntax.self) {
            let name = base.baseName.text
            if let first = name.first, first.isUppercase {
                references[name, default: []].insert(currentFile)
            }
        }
        return .visitChildren
    }

    // MARK: - Finalize

    func finalizeAnalysis() {
        for decl in declarations {
            let referencingFiles = references[decl.name] ?? []
            // Remove the declaring file — we only care about external references
            let externalFiles = referencingFiles.subtracting([decl.file])

            if externalFiles.isEmpty {
                addIssue(
                    severity: .info,
                    message: "'\(decl.name)' is only used in its declaring file "
                        + "and could be private",
                    filePath: decl.file,
                    lineNumber: getLineNumber(for: decl.node),
                    suggestion: "Add `private` access to narrow the scope of '\(decl.name)'.",
                    ruleName: .couldBePrivate
                )
            }
        }
    }

    func accept<T: PatternVisitorProtocol>(visitor: T) throws {
        for (_, sourceFile) in fileCache {
            visitor.walk(sourceFile)
        }
    }

    // MARK: - Helpers

    private func collectDeclarationIfEligible(
        _ name: String,
        modifiers: DeclModifierListSyntax,
        node: Syntax
    ) {
        // Only flag top-level declarations
        guard isTopLevel(node) else { return }

        // Skip types in test files — test structs are inherently file-scoped
        if currentFile.contains("Tests") || currentFile.hasSuffix("Test.swift") {
            return
        }

        // Skip types that already have explicit access control
        let hasExplicitAccess = modifiers.contains { modifier in
            let text = modifier.name.text
            return text == "private" || text == "fileprivate"
                || text == "public" || text == "open" || text == "internal"
        }
        guard !hasExplicitAccess else { return }

        declarations.append((name: name, file: currentFile, node: node))
        declaredTypeNames.insert(name)
    }

    private func isSwiftUIApp(_ node: StructDeclSyntax) -> Bool {
        node.inheritanceClause?.inheritedTypes.contains { inherited in
            inherited.type.as(IdentifierTypeSyntax.self)?.name.text == "App"
        } ?? false
    }

    private func hasMainAttribute(_ attributes: AttributeListSyntax) -> Bool {
        attributes.contains { element in
            element.as(AttributeSyntax.self)?.attributeName
                .as(IdentifierTypeSyntax.self)?.name.text == "main"
        }
    }

    private func isTopLevel(_ node: Syntax) -> Bool {
        guard let parent = node.parent,
              parent.is(CodeBlockItemSyntax.self),
              let grandparent = parent.parent,
              grandparent.is(CodeBlockItemListSyntax.self),
              let greatGrandparent = grandparent.parent,
              greatGrandparent.is(SourceFileSyntax.self) else { return false }
        return true
    }
}
