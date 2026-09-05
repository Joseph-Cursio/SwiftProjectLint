import Foundation
import SwiftProjectLintModels
import SwiftProjectLintVisitors
import SwiftSyntax

/// A SwiftSyntax visitor that detects direct instantiation of concrete service-like types
/// where dependency injection would improve testability and reduce coupling.
class DirectInstantiationVisitor: BasePatternVisitor {
    private var currentFilePath: String = ""
    private var insideFunctionOrClosure = 0

    /// Depth inside a `#Preview` macro or an `#if DEBUG` block. A counter rather than a
    /// flag because the two nest — a `#Preview` inside `#if DEBUG` is the ordinary
    /// spelling — and a flag would be cleared by whichever closed first.
    private var insidePreviewOrDebug = 0

    /// Names of the nominal types currently being visited, innermost last.
    /// Used to recognise a type that instantiates *itself* as a static member —
    /// the canonical singleton definition site, which is not a coupling smell.
    private var typeNameStack: [String] = []

    required init(pattern: SyntaxPattern, viewMode: SyntaxTreeViewMode = .sourceAccurate) {
        super.init(pattern: pattern, viewMode: viewMode)
    }

    override func setFilePath(_ filePath: String) {
        self.currentFilePath = filePath
    }

    // MARK: - Service-like call heuristic

    private func isServiceLikeCall(_ expr: ExprSyntax) -> String? {
        guard let call = expr.as(FunctionCallExprSyntax.self) else { return nil }
        let callee = call.calledExpression.description.trimmingCharacters(in: .whitespaces)
        guard callee.first?.isUppercase == true,
              ServiceTypeSuffix.matches(callee) else { return nil }
        return callee
    }

    // MARK: - Property wrapper detection

    private func hasPropertyWrapper(_ node: VariableDeclSyntax) -> Bool {
        for attribute in node.attributes {
            if let attr = attribute.as(AttributeSyntax.self),
               let name = attr.attributeName.as(IdentifierTypeSyntax.self)?.name.text,
               PropertyWrapper.stateStorageAttributeNames.contains(name) {
                return true
            }
        }
        return false
    }

    // MARK: - Stored property / local variable detection

    override func visit(_ node: VariableDeclSyntax) -> SyntaxVisitorContinueKind {
        // `#Preview` and `#if DEBUG` are composition contexts: the whole point of a
        // preview is to build a concrete object graph to look at, and a debug block is
        // scaffolding that never ships. Injecting a dependency there would mean routing
        // it in from somewhere, which is what the preview exists to avoid.
        guard insidePreviewOrDebug == 0 else { return .visitChildren }

        // Inside a function or closure: local variable — no wrapper check needed
        // Outside (stored property): skip if it has a property wrapper
        if insideFunctionOrClosure == 0, hasPropertyWrapper(node) {
            return .visitChildren
        }

        for binding in node.bindings {
            guard let initializer = binding.initializer else { continue }
            if let typeName = isServiceLikeCall(initializer.value) {
                // Exempt a type that vends an instance of itself as a `static`
                // member — `static let shared = Foo()` *inside* `Foo`. Publishing
                // your own `.shared` by instantiating yourself is the singleton
                // idiom (and the same shape covers namespaced constants like
                // `static let live = Client()`); it is a definition, not an
                // injectable dependency. The coupling worth flagging is the
                // `.shared` *access* at call sites, which `SingletonUsage` covers.
                if isStatic(node), typeNameStack.last == typeName {
                    continue
                }
                let paramName: String
                if let pattern = binding.pattern.as(IdentifierPatternSyntax.self) {
                    paramName = pattern.identifier.text
                } else {
                    paramName = "dependency"
                }
                _ = paramName // suppress unused warning — message uses typeName
                addIssue(
                    severity: .warning,
                    message: "Direct instantiation of '\(typeName)' detected — prefer dependency injection",
                    filePath: currentFilePath,
                    lineNumber: getLineNumber(for: Syntax(node)),
                    suggestion: "Inject '\(typeName)' through the initializer or use @StateObject/@EnvironmentObject",
                    ruleName: .directInstantiation
                )
            }
        }
        return .visitChildren
    }

    // MARK: - Static-member detection

    private func isStatic(_ node: VariableDeclSyntax) -> Bool {
        node.modifiers.contains { $0.name.tokenKind == .keyword(.static) }
    }

    // MARK: - Enclosing-type context tracking

    override func visit(_ node: ClassDeclSyntax) -> SyntaxVisitorContinueKind {
        typeNameStack.append(node.name.text)
        return .visitChildren
    }

    override func visitPost(_ _: ClassDeclSyntax) {
        typeNameStack.removeLast()
    }

    override func visit(_ node: StructDeclSyntax) -> SyntaxVisitorContinueKind {
        typeNameStack.append(node.name.text)
        return .visitChildren
    }

    override func visitPost(_ _: StructDeclSyntax) {
        typeNameStack.removeLast()
    }

    override func visit(_ node: EnumDeclSyntax) -> SyntaxVisitorContinueKind {
        typeNameStack.append(node.name.text)
        return .visitChildren
    }

    override func visitPost(_ _: EnumDeclSyntax) {
        typeNameStack.removeLast()
    }

    override func visit(_ node: ActorDeclSyntax) -> SyntaxVisitorContinueKind {
        typeNameStack.append(node.name.text)
        return .visitChildren
    }

    override func visitPost(_ _: ActorDeclSyntax) {
        typeNameStack.removeLast()
    }

    // MARK: - Function / closure context tracking

    override func visit(_ _: FunctionDeclSyntax) -> SyntaxVisitorContinueKind {
        insideFunctionOrClosure += 1
        return .visitChildren
    }

    override func visitPost(_ _: FunctionDeclSyntax) {
        insideFunctionOrClosure -= 1
    }

    override func visit(_ _: ClosureExprSyntax) -> SyntaxVisitorContinueKind {
        insideFunctionOrClosure += 1
        return .visitChildren
    }

    override func visitPost(_ _: ClosureExprSyntax) {
        insideFunctionOrClosure -= 1
    }

    // MARK: - Preview / debug context tracking

    override func visit(_ node: MacroExpansionDeclSyntax) -> SyntaxVisitorContinueKind {
        if node.macroName.text == "Preview" { insidePreviewOrDebug += 1 }
        return .visitChildren
    }

    override func visitPost(_ node: MacroExpansionDeclSyntax) {
        if node.macroName.text == "Preview" { insidePreviewOrDebug -= 1 }
    }

    // `#Preview { }` parses as a *declaration* among other declarations and as an
    // *expression* when it is the only item in the file, so both spellings have to be
    // tracked. Handling only the declaration form left a file containing nothing but a
    // preview still reporting — which is exactly the file a preview tends to live in.
    override func visit(_ node: MacroExpansionExprSyntax) -> SyntaxVisitorContinueKind {
        if node.macroName.text == "Preview" { insidePreviewOrDebug += 1 }
        return .visitChildren
    }

    override func visitPost(_ node: MacroExpansionExprSyntax) {
        if node.macroName.text == "Preview" { insidePreviewOrDebug -= 1 }
    }

    override func visit(_ node: IfConfigDeclSyntax) -> SyntaxVisitorContinueKind {
        if Self.isDebugBlock(node) { insidePreviewOrDebug += 1 }
        return .visitChildren
    }

    override func visitPost(_ node: IfConfigDeclSyntax) {
        if Self.isDebugBlock(node) { insidePreviewOrDebug -= 1 }
    }

    /// Whether any clause of an `#if` names `DEBUG`.
    ///
    /// Read off the condition's source text rather than parsed as an expression: the
    /// condition grammar admits `&&`, `!`, and nested parentheses, and this only has to
    /// answer whether the block is debug-only scaffolding. The same predicate must be used
    /// by `visit` and `visitPost` or the counter unbalances, which is why it is one
    /// function rather than the condition written twice.
    private static func isDebugBlock(_ node: IfConfigDeclSyntax) -> Bool {
        node.clauses.contains { $0.condition?.description.contains("DEBUG") == true }
    }
}
