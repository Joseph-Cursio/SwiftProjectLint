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

    /// Depth inside the program's designated entry point. See `insideEntryPoint`.
    private var insideEntryPoint = 0

    /// Whether the type currently being visited carries `@main`.
    private var mainAttributedTypeDepth: [Bool] = []

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

    // MARK: - File-local access-level pre-pass

    override func visit(_ node: SourceFileSyntax) -> SyntaxVisitorContinueKind {
        let collector = PrivateTypeDeclarationCollector(viewMode: .sourceAccurate)
        collector.walk(node)
        privatelyDeclaredTypes = collector.names
        if isMainSwiftFile { insideEntryPoint += 1 }
        return .visitChildren
    }

    // MARK: - Stored property / local variable detection

    override func visit(_ node: VariableDeclSyntax) -> SyntaxVisitorContinueKind {
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
    private func isExemptDefinitionSite(_ typeName: String, on node: VariableDeclSyntax) -> Bool {
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

    private func isStatic(_ node: VariableDeclSyntax) -> Bool {
        node.modifiers.contains { $0.name.tokenKind == .keyword(.static) }
    }

    // MARK: - Program entry point

    /// `main.swift` holds top-level code, which Swift permits in no other file: it *is* the
    /// program. Tracked by file name because there is no syntax to look at — the statements
    /// are simply at the top of the file.
    private var isMainSwiftFile: Bool {
        (currentFilePath as NSString).lastPathComponent == "main.swift"
    }

    /// Whether a function declaration is the entry point of an `@main` type.
    ///
    /// Both spellings. `static func main()` is the one `@main` calls, and a SwiftUI `App`\'s
    /// `init()` is where its `@State` containers are seeded — the Explorer target\'s file
    /// header describes exactly that as "its composition root injects the in-process SwiftLint
    /// backend instead of the subprocess one".
    private func isEntryPointMember(named name: String, isStatic: Bool) -> Bool {
        guard mainAttributedTypeDepth.last == true else { return false }
        return name == "main" && isStatic
    }

    // MARK: - Composition roots

    /// Whether `node` sits in a body that is assembling an object graph rather than reaching
    /// for one dependency.
    ///
    /// Dependency injection has to bottom out. Somewhere a concrete graph is built, and that
    /// place is allowed — required — to name every concrete type it wires together; the whole
    /// benefit of injecting elsewhere is that there is exactly one such place. Reporting each
    /// construction inside it turns one architectural fact into a warning per line.
    ///
    /// Two conditions, and the second is what keeps this from being a neighbour count. The
    /// body must construct at least three distinct service-like types, **and** it must keep at
    /// least one of them past its own return, by assigning to a stored property of the
    /// enclosing type. That is what separates assembling a graph from using several tools.
    ///
    /// The condition was added after measuring the first version, which had only the count.
    /// `ProjectAnalyzer.analyze(paths:)` builds four diagram generators, uses each once and
    /// returns a summary; it went silent while an identical `ClassDiagramGenerator()` forty
    /// lines below, in a function with fewer neighbours, kept reporting. A rule that answers
    /// differently for the same construction depending on how many siblings it has is drawing
    /// the line on syntax rather than substance — which is the fault this rule's own
    /// documentation already records having corrected once, over defaulted parameters.
    private func insideCompositionRoot(_ node: Syntax) -> Bool {
        guard let body = Self.enclosingBody(of: node) else { return false }
        let counter = ServiceConstructionCounter(viewMode: .sourceAccurate)
        counter.walk(body)
        guard counter.typeNames.count >= Self.compositionRootThreshold else { return false }
        return counter.retainsBeyondBody
    }

    /// How many *distinct* service-like types a body must construct before it can read as an
    /// assembler.
    ///
    /// Three, chosen by looking at what each value removes rather than by taste. At two, a
    /// function that reaches for a store and its index — the ordinary two-dependency case the
    /// rule exists to catch — would go silent. At three, with the retention condition, the
    /// corpus's roots are named and nothing else is: `AppState.constructCoreServices`,
    /// `assignStatelessServices`, `constructHigherLayers`, `ExtensionServiceContainer`\'s
    /// `commandHandler`, `KnowledgeGraph.init` — nine domain stores off one injected database
    /// — and the sandboxed `App`\'s `init`, whose file header calls itself a composition root
    /// in as many words.
    private static let compositionRootThreshold = 3

    /// The nearest enclosing function, initializer, or accessor body.
    ///
    /// Deliberately not the enclosing *type*: a type with ten service-typed stored properties
    /// is a container too, but its properties are usually declared without initializers and
    /// filled by one of these bodies, so the body is where the constructions actually are.
    private static func enclosingBody(of node: Syntax) -> Syntax? {
        var current: Syntax? = node.parent
        while let candidate = current {
            if let function = candidate.as(FunctionDeclSyntax.self) {
                return function.body.map(Syntax.init)
            }
            if let initializer = candidate.as(InitializerDeclSyntax.self) {
                return initializer.body.map(Syntax.init)
            }
            if let accessor = candidate.as(AccessorDeclSyntax.self) {
                return accessor.body.map(Syntax.init)
            }
            current = candidate.parent
        }
        return nil
    }

    // MARK: - Enclosing-type context tracking

    override func visit(_ node: ClassDeclSyntax) -> SyntaxVisitorContinueKind {
        typeNameStack.append(node.name.text)
        mainAttributedTypeDepth.append(Self.carriesMainAttribute(node.attributes))
        return .visitChildren
    }

    override func visitPost(_ _: ClassDeclSyntax) {
        typeNameStack.removeLast()
        mainAttributedTypeDepth.removeLast()
    }

    override func visit(_ node: StructDeclSyntax) -> SyntaxVisitorContinueKind {
        typeNameStack.append(node.name.text)
        mainAttributedTypeDepth.append(Self.carriesMainAttribute(node.attributes))
        return .visitChildren
    }

    override func visitPost(_ _: StructDeclSyntax) {
        typeNameStack.removeLast()
        mainAttributedTypeDepth.removeLast()
    }

    override func visit(_ node: EnumDeclSyntax) -> SyntaxVisitorContinueKind {
        typeNameStack.append(node.name.text)
        mainAttributedTypeDepth.append(Self.carriesMainAttribute(node.attributes))
        return .visitChildren
    }

    override func visitPost(_ _: EnumDeclSyntax) {
        typeNameStack.removeLast()
        mainAttributedTypeDepth.removeLast()
    }

    override func visit(_ node: ActorDeclSyntax) -> SyntaxVisitorContinueKind {
        typeNameStack.append(node.name.text)
        mainAttributedTypeDepth.append(Self.carriesMainAttribute(node.attributes))
        return .visitChildren
    }

    override func visitPost(_ _: ActorDeclSyntax) {
        typeNameStack.removeLast()
        mainAttributedTypeDepth.removeLast()
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
        if mainAttributedTypeDepth.last == true { insideEntryPoint += 1 }
        return .visitChildren
    }

    override func visitPost(_ _: InitializerDeclSyntax) {
        insideFunctionOrClosure -= 1
        if mainAttributedTypeDepth.last == true { insideEntryPoint -= 1 }
    }

    /// Whether a declaration carries `@main`.
    private static func carriesMainAttribute(_ attributes: AttributeListSyntax) -> Bool {
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

/// Counts the distinct service-like types constructed anywhere inside one body, and notes
/// whether the body keeps anything past its own return.
///
/// Every construction is counted, not only the ones the rule would report:
/// `self.runner = SwiftLintRunner()` is an assignment rather than a variable declaration, and
/// `try await BeadStore(path:)` wraps its call in two expressions, so a count of *findings*
/// would read `assignStatelessServices` — six services wired in eight lines — as reaching for
/// one.
private final class ServiceConstructionCounter: SyntaxVisitor {

    private(set) var typeNames: Set<String> = []

    /// Whether the body assigns to something that outlives it.
    ///
    /// `self.chatSessionStore = store` is the obvious spelling. The bare form matters as much:
    /// `handler = newHandler` inside `ExtensionServiceContainer`, `workspaceIndexer = indexer`
    /// inside an `AppState` extension, and `_ruleRegistry = State(initialValue: registry)` in a
    /// SwiftUI `App`\'s `init` all assign to a stored property without writing `self.`. Told
    /// apart from a local reassignment by name: every `let`/`var` the body itself binds is
    /// collected, and a target outside that set is a member.
    var retainsBeyondBody: Bool {
        assignedNames.contains { !locallyBoundNames.contains($0) } || assignsThroughSelf
    }

    private var locallyBoundNames: Set<String> = []
    private var assignedNames: Set<String> = []
    private var assignsThroughSelf = false

    override func visit(_ node: FunctionCallExprSyntax) -> SyntaxVisitorContinueKind {
        if let name = DirectInstantiationVisitor.constructedTypeName(of: node.calledExpression),
           ServiceTypeSuffix.matches(name) {
            typeNames.insert(name)
        }
        return .visitChildren
    }

    override func visit(_ node: PatternBindingSyntax) -> SyntaxVisitorContinueKind {
        if let identifier = node.pattern.as(IdentifierPatternSyntax.self) {
            locallyBoundNames.insert(identifier.identifier.text)
        }
        return .visitChildren
    }

    /// Assignment is read off `SequenceExprSyntax`, not `InfixOperatorExprSyntax`.
    ///
    /// An unfolded tree — which is what `Parser.parse` produces, and what every visitor here
    /// walks — represents `self.store = store` as a three-element sequence whose middle
    /// element is the `AssignmentExprSyntax`. `InfixOperatorExprSyntax` appears only after
    /// operator folding, which needs an operator table the linter never builds. Written the
    /// other way first, this gate compiled, its tests passed against hand-built trees, and it
    /// removed exactly nothing from the corpus.
    override func visit(_ node: SequenceExprSyntax) -> SyntaxVisitorContinueKind {
        let elements = Array(node.elements)
        guard elements.count >= 2,
              elements[1].as(AssignmentExprSyntax.self) != nil else { return .visitChildren }
        let target = elements[0]
        if let member = target.as(MemberAccessExprSyntax.self),
           member.base?.as(DeclReferenceExprSyntax.self)?.baseName.tokenKind == .keyword(.self) {
            assignsThroughSelf = true
        }
        if let reference = target.as(DeclReferenceExprSyntax.self) {
            assignedNames.insert(reference.baseName.text)
        }
        return .visitChildren
    }
}
