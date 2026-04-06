import SwiftProjectLintModels
import SwiftProjectLintRegistry
import SwiftProjectLintVisitors
import SwiftSyntax

/// Detects potential cross-actor calls missing `await`.
///
/// This is a heuristic rule — it tracks global actor annotations (`@MainActor`,
/// custom `@globalActor` types) on types and functions within the same file, then
/// flags calls that appear to cross actor boundaries without `await`.
///
/// Without full type information, this rule focuses on obvious cases:
/// - Calls to static methods on `@MainActor` types from non-isolated contexts
/// - Calls to explicitly actor-annotated free functions from a different context
/// - Method calls on variables whose type annotation matches a known actor-isolated type
final class GlobalActorMismatchVisitor: BasePatternVisitor {

    // MARK: - Tracked state

    /// Maps type names to their global actor annotation (e.g. "ViewModel" → "MainActor")
    private var actorAnnotatedTypes: [String: String] = [:]

    /// Maps function names to their global actor annotation
    private var actorAnnotatedFunctions: [String: String] = [:]

    /// Maps variable names to their declared type name (from type annotations only)
    private var variableTypes: [String: String] = [:]

    /// Stack of current isolation contexts (actor name or nil for non-isolated)
    private var isolationStack: [String?] = [nil]

    private var currentIsolation: String? { isolationStack.last.flatMap { $0 } }

    required init(pattern: SyntaxPattern, viewMode: SyntaxTreeViewMode = .sourceAccurate) {
        super.init(pattern: pattern, viewMode: viewMode)
    }

    // MARK: - First pass: collect actor-annotated declarations

    override func visit(_ node: ClassDeclSyntax) -> SyntaxVisitorContinueKind {
        let actorName = globalActorName(from: node.attributes)
        if let actorName {
            actorAnnotatedTypes[node.name.text] = actorName
        }
        isolationStack.append(actorName)
        return .visitChildren
    }

    override func visitPost(_ node: ClassDeclSyntax) {
        isolationStack.removeLast()
    }

    override func visit(_ node: StructDeclSyntax) -> SyntaxVisitorContinueKind {
        let actorName = globalActorName(from: node.attributes)
        if let actorName {
            actorAnnotatedTypes[node.name.text] = actorName
        }
        isolationStack.append(actorName)
        return .visitChildren
    }

    override func visitPost(_ node: StructDeclSyntax) {
        isolationStack.removeLast()
    }

    override func visit(_ node: EnumDeclSyntax) -> SyntaxVisitorContinueKind {
        let actorName = globalActorName(from: node.attributes)
        if let actorName {
            actorAnnotatedTypes[node.name.text] = actorName
        }
        isolationStack.append(actorName)
        return .visitChildren
    }

    override func visitPost(_ node: EnumDeclSyntax) {
        isolationStack.removeLast()
    }

    override func visit(_ node: FunctionDeclSyntax) -> SyntaxVisitorContinueKind {
        let actorName = globalActorName(from: node.attributes)
        if let actorName {
            actorAnnotatedFunctions[node.name.text] = actorName
        }
        // Track parameter types for instance call resolution
        for param in node.signature.parameterClause.parameters {
            let paramName = param.secondName?.text ?? param.firstName.text
            let typeName = param.type.trimmedDescription
            variableTypes[paramName] = typeName
        }
        isolationStack.append(actorName ?? currentIsolation)
        return .visitChildren
    }

    override func visitPost(_ node: FunctionDeclSyntax) {
        // Clean up parameter types to avoid leaking into outer scope
        for param in node.signature.parameterClause.parameters {
            let paramName = param.secondName?.text ?? param.firstName.text
            variableTypes.removeValue(forKey: paramName)
        }
        isolationStack.removeLast()
    }

    // MARK: - Track variable type annotations

    override func visit(_ node: VariableDeclSyntax) -> SyntaxVisitorContinueKind {
        for binding in node.bindings {
            guard let varName = binding.pattern
                .as(IdentifierPatternSyntax.self)?.identifier.text,
                  let typeAnnotation = binding.typeAnnotation else {
                continue
            }
            let typeName = typeAnnotation.type.trimmedDescription
            variableTypes[varName] = typeName
        }
        return .visitChildren
    }

    // MARK: - Detect cross-actor calls without await

    override func visit(_ node: FunctionCallExprSyntax) -> SyntaxVisitorContinueKind {
        guard isAwaitPreceding(node) == false else { return .visitChildren }

        // Case 1: Static call like ActorType.method()
        if let memberAccess = node.calledExpression.as(MemberAccessExprSyntax.self),
           let baseRef = memberAccess.base?.as(DeclReferenceExprSyntax.self) {
            let baseName = baseRef.baseName.text
            let methodName = memberAccess.declName.baseName.text

            // Static call on actor-annotated type
            if let calleeActor = actorAnnotatedTypes[baseName],
               calleeActor != currentIsolation {
                reportMismatch(
                    functionName: "\(baseName).\(methodName)",
                    calleeActor: calleeActor,
                    node: node
                )
                return .visitChildren
            }

            // Instance call on a variable with known actor-annotated type
            if let varType = variableTypes[baseName],
               let calleeActor = actorAnnotatedTypes[varType],
               calleeActor != currentIsolation {
                reportMismatch(
                    functionName: "\(baseName).\(methodName)",
                    calleeActor: calleeActor,
                    node: node
                )
                return .visitChildren
            }
        }

        // Case 2: Direct call to actor-annotated free function
        if let declRef = node.calledExpression.as(DeclReferenceExprSyntax.self) {
            let funcName = declRef.baseName.text
            if let calleeActor = actorAnnotatedFunctions[funcName],
               calleeActor != currentIsolation {
                reportMismatch(
                    functionName: funcName,
                    calleeActor: calleeActor,
                    node: node
                )
            }
        }

        return .visitChildren
    }

    // MARK: - Helpers

    private func globalActorName(from attributes: AttributeListSyntax) -> String? {
        for attr in attributes {
            guard let attrSyntax = attr.as(AttributeSyntax.self) else { continue }
            let name = attrSyntax.attributeName.trimmedDescription
            if name == "MainActor" || name.hasSuffix("Actor") {
                return name
            }
        }
        return nil
    }

    private func isAwaitPreceding(_ node: FunctionCallExprSyntax) -> Bool {
        // Walk up to find an AwaitExprSyntax wrapping this call
        var current: Syntax? = Syntax(node)
        while let parent = current?.parent {
            if parent.is(AwaitExprSyntax.self) { return true }
            // Stop at statement boundaries
            if parent.is(CodeBlockItemSyntax.self) { return false }
            current = parent
        }
        return false
    }

    private func reportMismatch(
        functionName: String,
        calleeActor: String,
        node: FunctionCallExprSyntax
    ) {
        let context = currentIsolation ?? "non-isolated"
        addIssue(
            severity: .warning,
            message: "Call to '\(functionName)' (@\(calleeActor)) from "
                + "\(context) context may cross actor boundaries without 'await'",
            filePath: getFilePath(for: Syntax(node)),
            lineNumber: getLineNumber(for: Syntax(node)),
            suggestion: "Add 'await' before the call, or ensure both the caller "
                + "and callee share the same actor isolation.",
            ruleName: .globalActorMismatch
        )
    }
}
