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

    /// Names of the types this file declares `private` or `fileprivate`, gathered in one
    /// pass over the file before any finding is reported. No project-wide prescan is needed
    /// and none would help: a `private` type is unreachable outside its own file, so the
    /// declaration is always here if it is anywhere.
    private var privatelyDeclaredTypes: Set<String> = []

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
        guard let call = expr.as(FunctionCallExprSyntax.self),
              let typeName = Self.constructedTypeName(of: call.calledExpression) else { return nil }
        guard ServiceTypeSuffix.matches(typeName),
              !MockTypeName.matches(typeName) else { return nil }

        // A `private` or `fileprivate` type cannot be injected: no caller outside the file
        // that declares it can name the type, so there is nowhere for a substitute to come
        // from and no test that could supply one. Taking the advice would mean *widening*
        // the type's access level in order to hide it — exporting an implementation detail
        // to make it injectable, which is the opposite trade from the one the rule offers.
        //
        // The shape this reaches is the single-use accumulator: a `private final class
        // Checker: SyntaxVisitor` constructed, walked, read for one flag and discarded, three
        // lines down from the pure function that owns it. Those functions are total kernels —
        // the thing this whole sweep is trying to produce — and the rule was reporting their
        // insides as coupling.
        if privatelyDeclaredTypes.contains(typeName) { return nil }

        return typeName
    }

    /// The name of the type an expression constructs, or `nil` when the expression is not a
    /// type reference at all.
    ///
    /// The suffix test used to run against `calledExpression.description` whole, which reads a
    /// *member call* as an instantiation whenever the member's own name happens to end in a
    /// service suffix. `DerivationStrategist.composedGenerator(forTypeName:)` is a `static func`
    /// returning a value; it was reported as "direct instantiation of
    /// 'DerivationStrategist.composedGenerator'", advice with no referent — there is no such
    /// type to inject. The last component decides, and it has to look like a type: `Module.Type()`
    /// is a construction, `Type.method()` is not.
    private static func constructedTypeName(of expr: ExprSyntax) -> String? {
        // `Foo<Bar>()` — the specialization wraps the type reference.
        if let specialized = expr.as(GenericSpecializationExprSyntax.self) {
            return constructedTypeName(of: specialized.expression)
        }
        // `Foo()`
        if let reference = expr.as(DeclReferenceExprSyntax.self) {
            let name = reference.baseName.text
            return name.first?.isUppercase == true ? name : nil
        }
        // `Module.Foo()` — a construction only if the trailing component names a type.
        if let member = expr.as(MemberAccessExprSyntax.self) {
            let name = member.declName.baseName.text
            return name.first?.isUppercase == true ? name : nil
        }
        return nil
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

    // MARK: - File-local access-level pre-pass

    override func visit(_ node: SourceFileSyntax) -> SyntaxVisitorContinueKind {
        let collector = PrivateTypeDeclarationCollector(viewMode: .sourceAccurate)
        collector.walk(node)
        privatelyDeclaredTypes = collector.names
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

/// Collects the names of every type a single file declares `private` or `fileprivate`.
///
/// A separate walk rather than bookkeeping inside the main visit, because the declaration can
/// follow the use: `AmbientStateReads.occur` builds its `Checker` on line 26 and the
/// `private final class Checker` sits on line 34, so a visitor that learned the access level
/// as it went would have already reported the construction by the time it read the
/// declaration.
private final class PrivateTypeDeclarationCollector: SyntaxVisitor {

    private(set) var names: Set<String> = []

    override func visit(_ node: ClassDeclSyntax) -> SyntaxVisitorContinueKind {
        record(node.name.text, node.modifiers)
        return .visitChildren
    }

    override func visit(_ node: StructDeclSyntax) -> SyntaxVisitorContinueKind {
        record(node.name.text, node.modifiers)
        return .visitChildren
    }

    override func visit(_ node: EnumDeclSyntax) -> SyntaxVisitorContinueKind {
        record(node.name.text, node.modifiers)
        return .visitChildren
    }

    override func visit(_ node: ActorDeclSyntax) -> SyntaxVisitorContinueKind {
        record(node.name.text, node.modifiers)
        return .visitChildren
    }

    private func record(_ name: String, _ modifiers: DeclModifierListSyntax) {
        let isFileLocal = modifiers.contains {
            $0.name.tokenKind == .keyword(.private) || $0.name.tokenKind == .keyword(.fileprivate)
        }
        if isFileLocal { names.insert(name) }
    }
}
