import Foundation
import SwiftProjectLintModels
import SwiftProjectLintVisitors
import SwiftSyntax

/// A SwiftSyntax visitor that detects direct instantiation of concrete service-like types
/// where dependency injection would improve testability and reduce coupling.
class DirectInstantiationVisitor: BasePatternVisitor, PackagePurityConsumer {

    /// `isPureKernel`, the kernel exemption.
    static let packagePurityInputs: PackagePurityInputs = [.cleanInstanceMethods]
    var currentFilePath: String = ""
    private var insideFunctionOrClosure = 0

    /// Depth inside a `#Preview` macro or an `#if DEBUG` block. A counter rather than a
    /// flag because the two nest — a `#Preview` inside `#if DEBUG` is the ordinary
    /// spelling — and a flag would be cleared by whichever closed first.
    private var insidePreviewOrDebug = 0

    /// Depth inside a SwiftUI `View`. See `isObservableViewState`.
    private var insideSwiftUIView = 0

    /// Depth inside the program's designated entry point. See `insideEntryPoint`.
    private var insideEntryPoint = 0

    /// Whether each type being visited, innermost last, is an entry type. See `isEntryType`.
    var entryTypeStack: [Bool] = []

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

        // A type that holds nothing a test could not supply has nothing to inject: a test that
        // wants different behaviour passes different arguments, not a different instance. See
        // `CleanInstanceMethodCatalog.isPureKernel(_:)` and SwiftProjectLint#163 — the issue this
        // closes, filed against this rule, and answered for both twins at once.
        if knownCleanInstanceMethods.isPureKernel(typeName) { return nil }

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

        // An `@Observable` model a view owns is view *state*, not a dependency. That is
        // already why `@State private var model = Model()` is exempt; this is the same
        // ownership one step deferred.
        //
        // The deferral is forced, not stylistic. An `@Environment` value cannot be read from a
        // property initializer, so a model that needs one is built in `.task` and stored into
        // an optional `@State`:
        //
        //     @Environment(AppState.self) private var appState
        //     @State private var viewModel: BeadsViewModel?
        //     ...
        //     .task { if viewModel == nil { viewModel = BeadsViewModel(appState: appState) } }
        //
        // That construction *is* the injection — `appState` arrives from the environment — and
        // the rule's suggestion names the pre-Observation API for a problem Observation does
        // not have. Seven of the corpus's findings were this pattern, written identically
        // seven times.
        if insideSwiftUIView > 0, knownObservableTypes.contains(typeName) { return nil }

        // A helper handed its own owner cannot be injected into that owner. `self` does not
        // exist before the initializer that would receive the substitute has run, so the
        // advice needs two-phase initialization — an optional stored property, filled after
        // construction — to buy a substitution nobody can use, because the helper is bound to
        // this owner anyway.
        //
        // Five of the corpus's findings are one file: `AccessibilityVisitor` splits its five
        // element checks into `lazy var buttonChecker = ButtonAccessibilityChecker(visitor:
        // self)` and four siblings, which is the ordinary way to keep a 900-line visitor from
        // being one type.
        if call.arguments.contains(where: { $0.expression.is(DeclReferenceExprSyntax.self)
            && $0.expression.as(DeclReferenceExprSyntax.self)?.baseName.tokenKind
                == .keyword(.self) }) {
            return nil
        }

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
    static func constructedTypeName(of expr: ExprSyntax) -> String? {
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

    func hasPropertyWrapper(_ node: VariableDeclSyntax) -> Bool {
        for attribute in node.attributes {
            if let attr = attribute.as(AttributeSyntax.self),
               let name = attr.attributeName.as(IdentifierTypeSyntax.self)?.name.text,
               PropertyWrapper.stateStorageAttributeNames.contains(name) {
                return true
            }
        }
        return false
    }

    // MARK: - File-local access-level pre-pass

    override func visit(_ node: SourceFileSyntax) -> SyntaxVisitorContinueKind {
        let collector = FileLocalTypeCollector(viewMode: .sourceAccurate)
        collector.walk(node)
        privatelyDeclaredTypes = collector.names
        if isMainSwiftFile { insideEntryPoint += 1 }
        return .visitChildren
    }

    // MARK: - Stored property / local variable detection

    override func visit(_ node: VariableDeclSyntax) -> SyntaxVisitorContinueKind {
        if isRuntimeDrivenMember(node) { insideEntryPoint += 1 }

        // The program's entry point is the composition root the language designates. There is
        // exactly one per program, everything else is reached from it, and it has nowhere
        // further out to push a construction.
        //
        // `#Preview` and `#if DEBUG` are composition contexts for a different reason: the
        // whole point of a preview is to build a concrete object graph to look at, and a debug
        // block is scaffolding that never ships. Injecting a dependency there would mean
        // routing it in from somewhere, which is what the preview exists to avoid.
        guard insideEntryPoint == 0, insidePreviewOrDebug == 0 else { return .visitChildren }

        // Inside a function or closure: local variable — no wrapper check needed
        // Outside (stored property): skip if it has a property wrapper
        if insideFunctionOrClosure == 0, hasPropertyWrapper(node) {
            return .visitChildren
        }

        for binding in node.bindings {
            guard let initializer = binding.initializer,
                  let typeName = isServiceLikeCall(initializer.value),
                  !isExemptDefinitionSite(typeName, on: node) else { continue }
            report(typeName, at: node)
        }
        return .visitChildren
    }

    override func visitPost(_ node: VariableDeclSyntax) {
        if isRuntimeDrivenMember(node) { insideEntryPoint -= 1 }
    }

    /// Whether a construction is a *definition* rather than a consumption.
    ///
    /// Two cases, and they are unrelated except in being the wrong end of the seam.
    ///
    /// A type that vends an instance of *itself* as a `static` member — `static let shared =
    /// Foo()` inside `Foo` — is defining the singleton (and the same shape covers namespaced
    /// constants like `static let live = Client()`). The coupling worth flagging is the
    /// `.shared` *access* at call sites, which `Singleton Usage` covers. The exemption is
    /// deliberately narrow: a `static` member instantiating a *different* service type, or a
    /// non-`static` member instantiating the enclosing type, is still reported.
    ///
    /// A composition root is allowed to know every concrete type it wires together, because
    /// the whole benefit of injecting everywhere else is that there is exactly one such place.
    func isExemptDefinitionSite(_ typeName: String, on node: VariableDeclSyntax) -> Bool {
        if isStatic(node), typeNameStack.last == typeName { return true }
        return insideCompositionRoot(Syntax(node))
    }

    private func report(_ typeName: String, at node: VariableDeclSyntax) {
        addIssue(
            severity: .warning,
            message: "Direct instantiation of '\(typeName)' detected — prefer dependency injection",
            filePath: currentFilePath,
            lineNumber: getLineNumber(for: Syntax(node)),
            suggestion: "Inject '\(typeName)' through the initializer or use @StateObject/@EnvironmentObject",
            ruleName: .directInstantiation
        )
    }

    // MARK: - Static-member detection

    func isStatic(_ node: VariableDeclSyntax) -> Bool {
        node.modifiers.contains { $0.name.tokenKind == .keyword(.static) }
    }

    // MARK: - Enclosing-type context tracking

    override func visit(_ node: ClassDeclSyntax) -> SyntaxVisitorContinueKind {
        typeNameStack.append(node.name.text)
        entryTypeStack.append(Self.isEntryType(node.attributes, node.inheritanceClause))
        if Self.isRuntimeConstructed(node.inheritanceClause) { insideEntryPoint += 1 }
        return .visitChildren
    }

    override func visitPost(_ node: ClassDeclSyntax) {
        typeNameStack.removeLast()
        entryTypeStack.removeLast()
        if Self.isRuntimeConstructed(node.inheritanceClause) { insideEntryPoint -= 1 }
    }

    override func visit(_ node: StructDeclSyntax) -> SyntaxVisitorContinueKind {
        typeNameStack.append(node.name.text)
        entryTypeStack.append(Self.isEntryType(node.attributes, node.inheritanceClause))
        if Self.isRuntimeConstructed(node.inheritanceClause) { insideEntryPoint += 1 }
        if isSwiftUIViewOnly(node) { insideSwiftUIView += 1 }
        return .visitChildren
    }

    override func visitPost(_ node: StructDeclSyntax) {
        typeNameStack.removeLast()
        entryTypeStack.removeLast()
        if Self.isRuntimeConstructed(node.inheritanceClause) { insideEntryPoint -= 1 }
        if isSwiftUIViewOnly(node) { insideSwiftUIView -= 1 }
    }

    override func visit(_ node: EnumDeclSyntax) -> SyntaxVisitorContinueKind {
        typeNameStack.append(node.name.text)
        entryTypeStack.append(Self.isEntryType(node.attributes, node.inheritanceClause))
        if Self.isRuntimeConstructed(node.inheritanceClause) { insideEntryPoint += 1 }
        return .visitChildren
    }

    override func visitPost(_ node: EnumDeclSyntax) {
        typeNameStack.removeLast()
        entryTypeStack.removeLast()
        if Self.isRuntimeConstructed(node.inheritanceClause) { insideEntryPoint -= 1 }
    }

    override func visit(_ node: ActorDeclSyntax) -> SyntaxVisitorContinueKind {
        typeNameStack.append(node.name.text)
        entryTypeStack.append(Self.isEntryType(node.attributes, node.inheritanceClause))
        if Self.isRuntimeConstructed(node.inheritanceClause) { insideEntryPoint += 1 }
        return .visitChildren
    }

    override func visitPost(_ node: ActorDeclSyntax) {
        typeNameStack.removeLast()
        entryTypeStack.removeLast()
        if Self.isRuntimeConstructed(node.inheritanceClause) { insideEntryPoint -= 1 }
    }

    // MARK: - Function / closure context tracking

    override func visit(_ node: FunctionDeclSyntax) -> SyntaxVisitorContinueKind {
        insideFunctionOrClosure += 1
        if isEntryPointMember(
            named: node.name.text,
            isStatic: node.modifiers.contains { $0.name.tokenKind == .keyword(.static) }
        ) {
            insideEntryPoint += 1
        }
        return .visitChildren
    }

    override func visitPost(_ node: FunctionDeclSyntax) {
        insideFunctionOrClosure -= 1
        if isEntryPointMember(
            named: node.name.text,
            isStatic: node.modifiers.contains { $0.name.tokenKind == .keyword(.static) }
        ) {
            insideEntryPoint -= 1
        }
    }

    /// A SwiftUI `App`\'s `init()` seeds the containers the whole program reads from. It is
    /// the same role `static func main()` plays for a command-line `@main`, and the two
    /// spellings are the two ways Swift writes an entry point.
    override func visit(_ _: InitializerDeclSyntax) -> SyntaxVisitorContinueKind {
        insideFunctionOrClosure += 1
        if entryTypeStack.last == true { insideEntryPoint += 1 }
        return .visitChildren
    }

    override func visitPost(_ _: InitializerDeclSyntax) {
        insideFunctionOrClosure -= 1
        if entryTypeStack.last == true { insideEntryPoint -= 1 }
    }

    /// Whether a declaration carries `@main`.
    static func carriesMainAttribute(_ attributes: AttributeListSyntax) -> Bool {
        attributes.contains { attribute in
            attribute.as(AttributeSyntax.self)?
                .attributeName.as(IdentifierTypeSyntax.self)?.name.text == "main"
        }
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
    static func isDebugBlock(_ node: IfConfigDeclSyntax) -> Bool {
        node.clauses.contains { $0.condition?.description.contains("DEBUG") == true }
    }
}
