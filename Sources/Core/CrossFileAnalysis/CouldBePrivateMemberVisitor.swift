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
    private var functionNestingDepth: Int = 0

    /// Names to skip — SwiftUI framework hooks, protocol requirements, etc.
    private static let ignoredNames: Set<String> = [
        "body", "init", "deinit", "hash", "encode", "decode",
        "description", "debugDescription", "hashValue",
        "makeBody", "makeUIView", "updateUIView",
        "makeNSView", "updateNSView", "sizeThatFits",
        // NSApplicationDelegate / UNUserNotificationCenterDelegate
        "applicationDidFinishLaunching", "applicationShouldTerminateAfterLastWindowClosed",
        "applicationDockMenu", "userNotificationCenter"
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
        // Only collect as a member if we're at the type level (not nested in another function)
        if functionNestingDepth == 0 {
            collectMemberIfEligible(
                name: node.name.text,
                kind: "func",
                modifiers: node.modifiers,
                node: Syntax(node)
            )
        }
        functionNestingDepth += 1
        return .visitChildren
    }

    override func visitPost(_ node: FunctionDeclSyntax) {
        functionNestingDepth -= 1
    }

    // Closures and computed property accessors also introduce local scope
    override func visit(_ node: ClosureExprSyntax) -> SyntaxVisitorContinueKind {
        functionNestingDepth += 1
        return .visitChildren
    }

    override func visitPost(_ node: ClosureExprSyntax) {
        functionNestingDepth -= 1
    }

    override func visit(_ node: AccessorDeclSyntax) -> SyntaxVisitorContinueKind {
        functionNestingDepth += 1
        return .visitChildren
    }

    override func visitPost(_ node: AccessorDeclSyntax) {
        functionNestingDepth -= 1
    }

    override func visit(_ node: VariableDeclSyntax) -> SyntaxVisitorContinueKind {
        // Skip if outside a type, or inside a function body (local variables)
        guard typeNestingDepth > 0, functionNestingDepth == 0 else { return .visitChildren }

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

            // Skip struct stored properties without default values — they're part of
            // the memberwise initializer and must remain accessible to callers.
            if isStructStoredPropertyWithoutDefault(varDecl) { return }
        }

        // Skip operators (==, <, etc.) — typically protocol conformance requirements
        if let funcDecl = node.as(FunctionDeclSyntax.self) {
            let funcName = funcDecl.name.text
            if funcName == "==" || funcName == "<" || funcName == ">" || funcName == "hash" {
                return
            }
        }

        // Skip members inside already-private types — they're already inaccessible
        if isInsidePrivateType(node) { return }

        declarations.append(MemberDeclaration(
            typeName: currentTypeName,
            memberName: name,
            memberKind: kind,
            file: currentFile,
            node: node
        ))
    }

    /// Returns true if this is a stored property on a struct with no default value.
    /// These are part of the memberwise initializer and cannot be private.
    private func isStructStoredPropertyWithoutDefault(_ varDecl: VariableDeclSyntax) -> Bool {
        // Must be inside a struct (check parent chain for StructDeclSyntax)
        var current: Syntax? = Syntax(varDecl)
        var isInStruct = false
        while let ancestor = current {
            if ancestor.is(StructDeclSyntax.self) { isInStruct = true; break }
            if ancestor.is(ClassDeclSyntax.self) { break }
            if ancestor.is(EnumDeclSyntax.self) { break }
            current = ancestor.parent
        }
        guard isInStruct else { return false }

        // Check if it's a stored property (no accessor block) without a default value
        for binding in varDecl.bindings {
            if binding.accessorBlock != nil { return false } // computed property
            if binding.initializer != nil { return false }    // has default value
        }
        return true
    }

    /// Returns true if the node is inside a type that is already `private`.
    private func isInsidePrivateType(_ node: Syntax) -> Bool {
        var current: Syntax? = node.parent
        while let ancestor = current {
            if let structDecl = ancestor.as(StructDeclSyntax.self) {
                return structDecl.modifiers.contains { $0.name.text == "private" }
            }
            if let classDecl = ancestor.as(ClassDeclSyntax.self) {
                return classDecl.modifiers.contains { $0.name.text == "private" }
            }
            if let enumDecl = ancestor.as(EnumDeclSyntax.self) {
                return enumDecl.modifiers.contains { $0.name.text == "private" }
            }
            current = ancestor.parent
        }
        return false
    }
}
