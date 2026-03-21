import SwiftSyntax

/// A cross-file visitor that detects internal (default access) methods and properties
/// that are only referenced in their declaring file and could be `private`.
///
/// **Strategy:** Since SwiftSyntax has no type resolution, we track member names
/// conservatively. A member is only flagged when its name does not appear in any
/// other file — this avoids false positives from same-named members on different types,
/// at the cost of missing common names like `name` or `reset()`.
///
/// **Phase 1 (walk):** Collect all non-private member declarations with their
/// declaring file, and record every identifier usage per file.
/// **Phase 2 (finalizeAnalysis):** Flag members whose name only appears in their
/// declaring file.
final class CouldBePrivateMemberVisitor: BasePatternVisitor, CrossFilePatternVisitorProtocol {
    let fileCache: [String: SourceFileSyntax]

    private struct MemberDeclaration {
        let typeName: String
        let memberName: String
        let memberKind: String   // "func", "var", "let"
        let file: String
        let node: Syntax
    }

    private var declarations: [MemberDeclaration] = []

    /// Tracks which files mention each identifier: name → Set<file>
    private var identifierUsages: [String: Set<String>] = [:]

    private var currentFile: String = ""
    private var currentTypeName: String = ""
    private var typeNestingDepth: Int = 0

    /// Names to skip — SwiftUI framework hooks, protocol requirements, etc.
    private static let ignoredNames: Set<String> = [
        "body", "init", "deinit", "hash", "encode", "decode",
        "description", "debugDescription", "hashValue",
        "makeBody", "makeUIView", "updateUIView",
        "makeNSView", "updateNSView",
    ]

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

    // MARK: - Track Current Type

    override func visit(_ node: StructDeclSyntax) -> SyntaxVisitorContinueKind {
        if typeNestingDepth == 0 { currentTypeName = node.name.text }
        typeNestingDepth += 1
        return .visitChildren
    }

    override func visitPost(_ node: StructDeclSyntax) {
        typeNestingDepth -= 1
        if typeNestingDepth == 0 { currentTypeName = "" }
    }

    override func visit(_ node: ClassDeclSyntax) -> SyntaxVisitorContinueKind {
        if typeNestingDepth == 0 { currentTypeName = node.name.text }
        typeNestingDepth += 1
        return .visitChildren
    }

    override func visitPost(_ node: ClassDeclSyntax) {
        typeNestingDepth -= 1
        if typeNestingDepth == 0 { currentTypeName = "" }
    }

    override func visit(_ node: EnumDeclSyntax) -> SyntaxVisitorContinueKind {
        if typeNestingDepth == 0 { currentTypeName = node.name.text }
        typeNestingDepth += 1
        return .visitChildren
    }

    override func visitPost(_ node: EnumDeclSyntax) {
        typeNestingDepth -= 1
        if typeNestingDepth == 0 { currentTypeName = "" }
    }

    override func visit(_ node: ActorDeclSyntax) -> SyntaxVisitorContinueKind {
        if typeNestingDepth == 0 { currentTypeName = node.name.text }
        typeNestingDepth += 1
        return .visitChildren
    }

    override func visitPost(_ node: ActorDeclSyntax) {
        typeNestingDepth -= 1
        if typeNestingDepth == 0 { currentTypeName = "" }
    }

    // MARK: - Collect Declarations

    override func visit(_ node: FunctionDeclSyntax) -> SyntaxVisitorContinueKind {
        collectMemberIfEligible(
            name: node.name.text,
            kind: "func",
            modifiers: node.modifiers,
            node: Syntax(node)
        )
        return .visitChildren
    }

    override func visit(_ node: VariableDeclSyntax) -> SyntaxVisitorContinueKind {
        // Skip if inside a function body (local variables)
        guard typeNestingDepth > 0 else { return .visitChildren }

        let keyword = node.bindingSpecifier.text  // "var" or "let"
        for binding in node.bindings {
            if let pattern = binding.pattern.as(IdentifierPatternSyntax.self) {
                collectMemberIfEligible(
                    name: pattern.identifier.text,
                    kind: keyword,
                    modifiers: node.modifiers,
                    node: Syntax(node)
                )
                break
            }
        }
        return .visitChildren
    }

    // MARK: - Collect References

    override func visit(_ node: DeclReferenceExprSyntax) -> SyntaxVisitorContinueKind {
        identifierUsages[node.baseName.text, default: []].insert(currentFile)
        return .visitChildren
    }

    override func visit(_ node: MemberAccessExprSyntax) -> SyntaxVisitorContinueKind {
        let memberName = node.declName.baseName.text
        identifierUsages[memberName, default: []].insert(currentFile)
        return .visitChildren
    }

    // MARK: - Finalize

    func finalizeAnalysis() {
        for decl in declarations {
            let usageFiles = identifierUsages[decl.memberName] ?? []
            let externalFiles = usageFiles.subtracting([decl.file])

            if externalFiles.isEmpty {
                addIssue(
                    severity: .info,
                    message: "'\(decl.typeName).\(decl.memberName)' is only used in its "
                        + "declaring file and could be private",
                    filePath: decl.file,
                    lineNumber: getLineNumber(for: decl.node),
                    suggestion: "Add `private` to '\(decl.memberKind) \(decl.memberName)' "
                        + "to narrow its scope.",
                    ruleName: .couldBePrivateMember
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

    private func collectMemberIfEligible(
        name: String,
        kind: String,
        modifiers: DeclModifierListSyntax,
        node: Syntax
    ) {
        // Must be inside a type
        guard !currentTypeName.isEmpty else { return }

        // Skip test files
        if currentFile.contains("Tests") || currentFile.hasSuffix("Test.swift") {
            return
        }

        // Skip ignored names
        guard !Self.ignoredNames.contains(name) else { return }

        // Skip members with explicit access control
        let hasExplicitAccess = modifiers.contains { modifier in
            let text = modifier.name.text
            return text == "private" || text == "fileprivate"
                || text == "public" || text == "open" || text == "internal"
        }
        guard !hasExplicitAccess else { return }

        // Skip overrides — they implement a superclass requirement
        let isOverride = modifiers.contains { $0.name.text == "override" }
        guard !isOverride else { return }

        // Skip @objc members — may be called via selectors
        let hasObjc = node.as(FunctionDeclSyntax.self)?.attributes.contains {
            $0.description.contains("@objc")
        } ?? false
        guard !hasObjc else { return }

        // Skip property wrapper-attributed properties (@State, @Binding, etc.)
        if let varDecl = node.as(VariableDeclSyntax.self) {
            let hasWrapper = varDecl.attributes.contains {
                $0.as(AttributeSyntax.self) != nil
            }
            if hasWrapper { return }
        }

        declarations.append(MemberDeclaration(
            typeName: currentTypeName,
            memberName: name,
            memberKind: kind,
            file: currentFile,
            node: node
        ))
    }
}
