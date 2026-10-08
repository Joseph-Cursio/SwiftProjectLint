import SwiftSyntax

/// Where the code at one point in a file runs.
enum ExecutionContext {
    /// Isolated to the main actor. The text says why.
    case mainActor(String)
    /// Synchronous code in an `@Observable` / `ObservableObject` model: not isolated, but SwiftUI
    /// calls it from the main actor.
    case calledFromMain(String)
    /// Anywhere else, or nothing says.
    case elsewhere

    var reason: String? {
        switch self {
        case .mainActor(let reason), .calledFromMain(let reason): reason
        case .elsewhere: nil
        }
    }

    init(_ isolation: TypeIsolation) {
        switch isolation {
        case .mainActor(let reason): self = .mainActor(reason)
        case .viewModel(let reason): self = .calledFromMain(reason)
        case .elsewhere: self = .elsewhere
        }
    }
}

/// Walks one file, tracking where each scope runs, and collects the blocking calls made on the
/// main actor.
///
/// Scopes nest the way Swift's isolation does. A member takes its type's isolation unless it
/// says otherwise. A nested type does **not** take its outer type's. A closure takes its
/// enclosing scope's, except where the API it is handed to moves it (`ClosureHandOff`).
final class MainActorBlockingCallScanner: SyntaxVisitor {

    struct Finding {
        let node: FunctionCallExprSyntax
        let call: BlockingCall
        let reason: String
    }

    private(set) var findings: [Finding] = []

    private let table: MainActorTypeTable
    private let fileDefaultsToMainActor: Bool
    private let fileContext: ExecutionContext
    private var stack: [ExecutionContext] = []

    private var current: ExecutionContext { stack.last ?? fileContext }

    init(table: MainActorTypeTable, fileDefaultsToMainActor: Bool) {
        self.table = table
        self.fileDefaultsToMainActor = fileDefaultsToMainActor
        fileContext = fileDefaultsToMainActor
            ? .mainActor("its target defaults to MainActor isolation") : .elsewhere
        super.init(viewMode: .sourceAccurate)
    }

    // MARK: - Calls

    override func visit(_ node: FunctionCallExprSyntax) -> SyntaxVisitorContinueKind {
        guard let reason = current.reason,
              let call = BlockingCallCatalog.match(node),
              Self.isAwaited(node) == false else { return .visitChildren }
        if call.kind == .wait, BlockingCallCatalog.isReportedBySemaphoreRule(node) {
            return .visitChildren
        }
        findings.append(Finding(node: node, call: call, reason: reason))
        return .visitChildren
    }

    /// `await reader.contents(atPath:)` suspends instead of blocking; only a synchronous call
    /// holds the thread.
    static func isAwaited(_ node: FunctionCallExprSyntax) -> Bool {
        var current = Syntax(node)
        while let parent = current.parent {
            if parent.is(AwaitExprSyntax.self) {
                return true
            }
            guard parent.is(TryExprSyntax.self) || parent.is(OptionalChainingExprSyntax.self)
                || parent.is(ForceUnwrapExprSyntax.self) else { return false }
            current = parent
        }
        return false
    }

    // MARK: - Types

    override func visit(_ node: ClassDeclSyntax) -> SyntaxVisitorContinueKind { enterType(node) }
    override func visitPost(_: ClassDeclSyntax) { stack.removeLast() }

    override func visit(_ node: StructDeclSyntax) -> SyntaxVisitorContinueKind { enterType(node) }
    override func visitPost(_: StructDeclSyntax) { stack.removeLast() }

    override func visit(_ node: EnumDeclSyntax) -> SyntaxVisitorContinueKind { enterType(node) }
    override func visitPost(_: EnumDeclSyntax) { stack.removeLast() }

    override func visit(_ node: ActorDeclSyntax) -> SyntaxVisitorContinueKind { enterType(node) }
    override func visitPost(_: ActorDeclSyntax) { stack.removeLast() }

    // Protocol bodies hold requirements, not code.
    override func visit(_: ProtocolDeclSyntax) -> SyntaxVisitorContinueKind { .skipChildren }

    override func visit(_ node: ExtensionDeclSyntax) -> SyntaxVisitorContinueKind {
        stack.append(extensionContext(node))
        return .visitChildren
    }

    override func visitPost(_: ExtensionDeclSyntax) { stack.removeLast() }

    private func enterType(_ decl: some DeclGroupSyntax) -> SyntaxVisitorContinueKind {
        let record = MainActorTypeTable.record(for: decl, defaultsToMainActor: fileDefaultsToMainActor)
        let name = MainActorTypeTable.declName(decl)
        stack.append(table.resolve(record, named: name, visiting: []).map(ExecutionContext.init) ?? .elsewhere)
        return .visitChildren
    }

    private func extensionContext(_ node: ExtensionDeclSyntax) -> ExecutionContext {
        let name = MainActorTypeTable.simpleName(node.extendedType)
        if let explicit = MainActorTypeTable.explicitIsolation(
            attributes: node.attributes, modifiers: node.modifiers, subject: "this extension of '\(name)'"
        ) {
            return ExecutionContext(explicit)
        }
        // A conformance added here isolates the members declared here.
        let added = MainActorTypeTable.inheritedNames(node.inheritanceClause)
        if let conformance = added.first(where: table.isMainActorProtocol) {
            return .mainActor("this extension conforms '\(name)' to \(conformance), which is @MainActor")
        }
        return table.isolation(of: name).map(ExecutionContext.init) ?? fileContext
    }

    // MARK: - Members

    override func visit(_ node: FunctionDeclSyntax) -> SyntaxVisitorContinueKind {
        enterMember(
            attributes: node.attributes, modifiers: node.modifiers, subject: "'\(node.name.text)()'",
            isAsync: node.signature.effectSpecifiers?.asyncSpecifier != nil
        )
    }

    override func visitPost(_: FunctionDeclSyntax) { stack.removeLast() }

    override func visit(_ node: InitializerDeclSyntax) -> SyntaxVisitorContinueKind {
        enterMember(
            attributes: node.attributes, modifiers: node.modifiers, subject: "'init'",
            isAsync: node.signature.effectSpecifiers?.asyncSpecifier != nil
        )
    }

    override func visitPost(_: InitializerDeclSyntax) { stack.removeLast() }

    override func visit(_ node: VariableDeclSyntax) -> SyntaxVisitorContinueKind {
        let name = node.bindings.first?.pattern.trimmedDescription ?? "property"
        return enterMember(
            attributes: node.attributes, modifiers: node.modifiers, subject: "'\(name)'", isAsync: false
        )
    }

    override func visitPost(_: VariableDeclSyntax) { stack.removeLast() }

    override func visit(_ node: SubscriptDeclSyntax) -> SyntaxVisitorContinueKind {
        enterMember(attributes: node.attributes, modifiers: node.modifiers, subject: "'subscript'", isAsync: false)
    }

    override func visitPost(_: SubscriptDeclSyntax) { stack.removeLast() }

    override func visit(_ node: AccessorDeclSyntax) -> SyntaxVisitorContinueKind {
        enterMember(
            attributes: node.attributes, modifiers: DeclModifierListSyntax([]), subject: "the accessor",
            isAsync: node.effectSpecifiers?.asyncSpecifier != nil
        )
    }

    override func visitPost(_: AccessorDeclSyntax) { stack.removeLast() }

    /// A deinitializer is not isolated unless it says `isolated deinit`.
    override func visit(_ node: DeinitializerDeclSyntax) -> SyntaxVisitorContinueKind {
        let isIsolated = node.modifiers.contains { $0.name.tokenKind == .keyword(.isolated) }
        stack.append(isIsolated ? current : .elsewhere)
        return .visitChildren
    }

    override func visitPost(_: DeinitializerDeclSyntax) { stack.removeLast() }

    private func enterMember(
        attributes: AttributeListSyntax,
        modifiers: DeclModifierListSyntax,
        subject: String,
        isAsync: Bool
    ) -> SyntaxVisitorContinueKind {
        if let explicit = MainActorTypeTable.explicitIsolation(
            attributes: attributes, modifiers: modifiers, subject: subject
        ) {
            stack.append(ExecutionContext(explicit))
        } else if isAsync, case .calledFromMain = current {
            // An async method of an unisolated model runs wherever its executor puts it, not on
            // the caller; only its synchronous members are pinned to SwiftUI's thread.
            stack.append(.elsewhere)
        } else {
            stack.append(current)
        }
        return .visitChildren
    }

    // MARK: - Closures

    override func visit(_ node: ClosureExprSyntax) -> SyntaxVisitorContinueKind {
        stack.append(closureContext(node))
        return .visitChildren
    }

    override func visitPost(_: ClosureExprSyntax) { stack.removeLast() }

    private func closureContext(_ closure: ClosureExprSyntax) -> ExecutionContext {
        if let attributes = closure.signature?.attributes {
            if MainActorTypeTable.hasAttribute(attributes, named: "MainActor") {
                return .mainActor("the closure is @MainActor")
            }
            if MainActorTypeTable.hasAttribute(attributes, named: "Sendable")
                || MainActorTypeTable.hasAttribute(attributes, named: "concurrent") {
                return .elsewhere
            }
        }
        let handOff = ClosureHandOff.classify(closure)
        switch handOff {
        case .mainActor(let place):
            return .mainActor("it runs \(place)")

        case .elsewhere:
            return .elsewhere

        case .task, .inherits:
            break
        }
        // `Task { }` and async closures in an unisolated model run on the global executor.
        let leavesCaller = handOff == .task || closure.signature?.effectSpecifiers?.asyncSpecifier != nil
        if leavesCaller, case .calledFromMain = current {
            return .elsewhere
        }
        return current
    }
}

/// Where an API runs a closure handed to it.
enum ClosureHandOff: Equatable {
    /// Always on the main actor, whatever the caller: `MainActor.run`, `DispatchQueue.main.async`.
    case mainActor(String)
    /// Off the caller's actor: `Task.detached`, `DispatchQueue.global().async`, `addTask`.
    case elsewhere
    /// `Task { }`: the caller's actor, if it has one.
    case task
    /// Run in place, or nothing says otherwise: `map`, `withAnimation`, a `Button` action.
    case inherits

    private static let mainActorCallees: [String: String] = [
        "MainActor.run": "inside MainActor.run",
        "MainActor.assumeIsolated": "inside MainActor.assumeIsolated",
        "DispatchQueue.main.async": "on DispatchQueue.main",
        "DispatchQueue.main.asyncAfter": "on DispatchQueue.main",
        "DispatchQueue.main.sync": "on DispatchQueue.main",
        "DispatchQueue.main.asyncAndWait": "on DispatchQueue.main",
        "OperationQueue.main.addOperation": "on OperationQueue.main",
        "RunLoop.main.perform": "on RunLoop.main"
    ]

    /// Members that run their closure somewhere other than the caller. `queue.sync { }` is not
    /// one: the caller waits for it, so blocking work inside still blocks the caller.
    private static let elsewhereMembers: Set<String> = [
        "detached", "detachNewThread", "addTask", "addTaskUnlessCancelled",
        "async", "asyncAfter", "addOperation", "perform",
        "dataTask", "downloadTask", "uploadTask"
    ]

    static func classify(_ closure: ClosureExprSyntax) -> Self {
        guard let call = receivingCall(of: closure) else { return .inherits }
        let callee = nameChain(call.calledExpression)
        if let callee, let place = mainActorCallees[callee] {
            return .mainActor(place)
        }
        if callee == "Task" {
            return .task
        }
        if callee == "Thread" {
            return .elsewhere
        }
        guard let member = call.calledExpression.as(MemberAccessExprSyntax.self) else { return .inherits }
        return elsewhereMembers.contains(member.declName.baseName.text) ? .elsewhere : .inherits
    }

    /// `DispatchQueue.main.async` for a callee made only of names, `nil` for anything else.
    ///
    /// Never the callee's source text: in a modifier chain the callee of `.onAppear { }` is the
    /// whole `VStack { … }.padding().onAppear`, and printing it for every closure in a large
    /// `body` would cost the size of the body each time.
    private static func nameChain(_ expression: ExprSyntax) -> String? {
        var names: [String] = []
        var current = expression
        while true {
            if let reference = current.as(DeclReferenceExprSyntax.self) {
                names.append(reference.baseName.text)
                return names.reversed().joined(separator: ".")
            }
            if let generic = current.as(GenericSpecializationExprSyntax.self) {
                current = generic.expression
                continue
            }
            guard let member = current.as(MemberAccessExprSyntax.self), let base = member.base else { return nil }
            names.append(member.declName.baseName.text)
            current = base
        }
    }

    /// The call `closure` is an argument to, trailing or labeled. `nil` for a closure called in
    /// place (`{ … }()`) or stored in a variable.
    private static func receivingCall(of closure: ClosureExprSyntax) -> FunctionCallExprSyntax? {
        if let call = closure.parent?.as(FunctionCallExprSyntax.self) {
            return call.trailingClosure?.id == closure.id ? call : nil
        }
        if closure.parent?.is(MultipleTrailingClosureElementSyntax.self) == true {
            return closure.parent?.parent?.parent?.as(FunctionCallExprSyntax.self)
        }
        if closure.parent?.is(LabeledExprSyntax.self) == true {
            return closure.parent?.parent?.parent?.as(FunctionCallExprSyntax.self)
        }
        return nil
    }
}
