import SwiftProjectLintModels
import SwiftProjectLintRegistry
import SwiftProjectLintVisitors
import SwiftSyntax

/// A SwiftSyntax visitor that detects variable shadowing across nested scopes.
///
/// Flags inner-scope declarations that reuse a name from an outer scope,
/// but **ignores** idiomatic Swift patterns:
/// - `if let x = x` / `if let x` (Swift 5.7+ shorthand)
/// - `guard let x = x` / `guard let x`
/// - `if let x = x as? T` (conditional type cast binding)
/// - `guard let self = self` / `guard let self` (weak-to-strong self capture)
/// - Closure parameters (closures create their own scope; reusing names is idiomatic)
/// - Rebinding with transform (`let x = x.cleaned()`, `let x = transform(x)`)
/// - Locals in methods that match stored property names (Swift uses `self.` for disambiguation)
/// - Variables shadowing a for-loop iteration variable or for-loop body variable
/// - `for x in x` where the iteration variable matches the sequence expression
final class VariableShadowingVisitor: BasePatternVisitor {

    private enum ScopeKind {
        case typeMember    // struct/class/enum/extension body
        case codeBlock     // function body, if/else, do, etc.
        case closure
        case forLoop       // for-statement scope (holds iteration variable)
        case forLoopBody   // code block that is the body of a for-statement
    }

    private struct ScopeFrame {
        var kind: ScopeKind
        var names: [String] = []
    }

    /// Each frame maps variable names declared in that scope.
    private var scopeStack: [ScopeFrame] = [ScopeFrame(kind: .codeBlock)]

    required init(pattern: SyntaxPattern, viewMode: SyntaxTreeViewMode = .sourceAccurate) {
        super.init(pattern: pattern, viewMode: viewMode)
    }

    override func reset() {
        super.reset()
        scopeStack = [ScopeFrame(kind: .codeBlock)]
    }

    // MARK: - Scope Tracking

    override func visit(_ node: MemberBlockSyntax) -> SyntaxVisitorContinueKind {
        scopeStack.append(ScopeFrame(kind: .typeMember))
        return .visitChildren
    }

    override func visitPost(_ node: MemberBlockSyntax) {
        _ = scopeStack.popLast()
    }

    override func visit(_ node: CodeBlockSyntax) -> SyntaxVisitorContinueKind {
        let kind: ScopeKind = node.parent?.is(ForStmtSyntax.self) == true ? .forLoopBody : .codeBlock
        scopeStack.append(ScopeFrame(kind: kind))
        return .visitChildren
    }

    override func visitPost(_ node: CodeBlockSyntax) {
        _ = scopeStack.popLast()
    }

    override func visit(_ node: ClosureExprSyntax) -> SyntaxVisitorContinueKind {
        scopeStack.append(ScopeFrame(kind: .closure))
        if let signature = node.signature {
            registerClosureParameters(signature)
        }
        return .visitChildren
    }

    override func visitPost(_ node: ClosureExprSyntax) {
        _ = scopeStack.popLast()
    }

    override func visit(_ node: ForStmtSyntax) -> SyntaxVisitorContinueKind {
        scopeStack.append(ScopeFrame(kind: .forLoop))
        if let identifier = node.pattern.as(IdentifierPatternSyntax.self) {
            let name = identifier.identifier.text
            // Skip shadow check when the sequence references the same name
            // (e.g. `for environ in environ` — analogous to `if let x = x`).
            if sequenceReferences(name: name, in: node.sequence) == false {
                checkShadow(name: name, node: Syntax(node.pattern), severity: .error)
            }
            registerInCurrentScope(name)
        }
        return .visitChildren
    }

    override func visitPost(_ node: ForStmtSyntax) {
        _ = scopeStack.popLast()
    }

    // MARK: - Variable Declarations

    override func visit(_ node: VariableDeclSyntax) -> SyntaxVisitorContinueKind {
        for binding in node.bindings {
            guard let identifier = binding.pattern.as(IdentifierPatternSyntax.self) else { continue }
            let name = identifier.identifier.text

            // Skip `_` placeholder names
            guard name != "_" else { continue }

            // Skip rebinding transforms like `let x = x.cleaned()` or `let x = transform(x)`
            // — the developer clearly knows about the outer variable.
            if initializerReferences(name: name, in: binding) == false {
                checkShadow(name: name, node: Syntax(binding.pattern), severity: .error)
            }
            registerInCurrentScope(name)
        }
        return .visitChildren
    }

    // MARK: - Function Parameters

    override func visit(_ node: FunctionDeclSyntax) -> SyntaxVisitorContinueKind {
        for parameter in node.signature.parameterClause.parameters {
            let name = parameter.secondName?.text ?? parameter.firstName.text
            guard name != "_" else { continue }
            // Only flag if shadowing a *local* variable, not a type property.
            // Function parameters matching type property names is idiomatic Swift
            // (e.g. init(configuration:), func process(name:)).
            checkShadowLocalOnly(name: name, node: Syntax(parameter), severity: .error)
        }
        return .visitChildren
    }

    // MARK: - Private Helpers

    /// Registers closure parameters in the current scope **without** checking
    /// for shadows. Closures create their own scope, and reusing names from
    /// an outer scope is idiomatic Swift (e.g. `mutex.withLock { value in }`).
    private func registerClosureParameters(_ signature: ClosureSignatureSyntax) {
        if let parameterClause = signature.parameterClause {
            switch parameterClause {
            case .parameterClause(let clause):
                for parameter in clause.parameters {
                    let name = parameter.secondName?.text ?? parameter.firstName.text
                    guard name != "_" else { continue }
                    registerInCurrentScope(name)
                }
            case .simpleInput(let list):
                for parameter in list {
                    let name = parameter.name.text
                    guard name != "_" else { continue }
                    registerInCurrentScope(name)
                }
            }
        }
    }

    private func registerInCurrentScope(_ name: String) {
        guard scopeStack.isEmpty == false else { return }
        scopeStack[scopeStack.count - 1].names.append(name)
    }

    /// Check only local code scopes, skipping type-member scopes (stored
    /// properties) and for-loop scopes (iteration variables). Function
    /// parameters matching type property names is idiomatic Swift, and
    /// reusing a for-loop variable name in a nested loop is common.
    private func checkShadowLocalOnly(name: String, node: Syntax, severity: IssueSeverity) {
        for frame in scopeStack where frame.names.contains(name) {
            // Skip type-member scopes — locals matching properties is idiomatic
            guard frame.kind != .typeMember else { continue }
            // Skip for-loop scopes — reusing iteration variable names is common
            guard frame.kind != .forLoop else { continue }
            // Skip for-loop body scopes — variables are short-lived per iteration
            guard frame.kind != .forLoopBody else { continue }
            addIssue(
                severity: severity,
                message: "Variable '\(name)' shadows a declaration from an outer scope",
                filePath: getFilePath(for: node),
                lineNumber: getLineNumber(for: node),
                suggestion: "Rename the inner variable to avoid confusion with the outer '\(name)'",
                ruleName: .variableShadowing
            )
            return
        }
    }

    private func checkShadow(name: String, node: Syntax, severity: IssueSeverity) {
        // Check all frames except the current (topmost) one
        let outerFrames = scopeStack.dropLast()
        for frame in outerFrames where frame.names.contains(name) {
            // Skip type-member scopes — locals matching properties is idiomatic
            guard frame.kind != .typeMember else { continue }
            // Skip for-loop scopes — reusing iteration variable names is common
            guard frame.kind != .forLoop else { continue }
            // Skip for-loop body scopes — variables are short-lived per iteration
            guard frame.kind != .forLoopBody else { continue }
            addIssue(
                severity: severity,
                message: "Variable '\(name)' shadows a declaration from an outer scope",
                filePath: getFilePath(for: node),
                lineNumber: getLineNumber(for: node),
                suggestion: "Rename the inner variable to avoid confusion with the outer '\(name)'",
                ruleName: .variableShadowing
            )
            return
        }
    }

    /// Returns `true` when `binding`'s initializer contains a reference to `name`.
    /// Used to distinguish ambiguous shadows (e.g. `let config = config.cleaned()`)
    /// from clear-cut ones (e.g. `let config = 42`).
    private func initializerReferences(name: String, in binding: PatternBindingSyntax) -> Bool {
        guard let initializer = binding.initializer else { return false }
        return initializer.value.tokens(viewMode: .sourceAccurate).contains { token in
            token.tokenKind == .identifier(name)
        }
    }

    /// Returns `true` when a for-loop's sequence expression references `name`.
    /// Used to skip `for x in x` patterns (analogous to `if let x = x`).
    private func sequenceReferences(name: String, in sequence: ExprSyntax) -> Bool {
        sequence.tokens(viewMode: .sourceAccurate).contains { token in
            token.tokenKind == .identifier(name)
        }
    }

}
