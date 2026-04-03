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
final class VariableShadowingVisitor: BasePatternVisitor {

    /// Each frame maps variable names declared in that scope.
    private var scopeStack: [[String]] = [[]]

    required init(pattern: SyntaxPattern, viewMode: SyntaxTreeViewMode = .sourceAccurate) {
        super.init(pattern: pattern, viewMode: viewMode)
    }

    override func reset() {
        super.reset()
        scopeStack = [[]]
    }

    // MARK: - Scope Tracking

    override func visit(_ node: CodeBlockSyntax) -> SyntaxVisitorContinueKind {
        scopeStack.append([])
        return .visitChildren
    }

    override func visitPost(_ node: CodeBlockSyntax) {
        _ = scopeStack.popLast()
    }

    override func visit(_ node: ClosureExprSyntax) -> SyntaxVisitorContinueKind {
        scopeStack.append([])
        if let signature = node.signature {
            registerClosureParameters(signature)
        }
        return .visitChildren
    }

    override func visitPost(_ node: ClosureExprSyntax) {
        _ = scopeStack.popLast()
    }

    override func visit(_ node: ForStmtSyntax) -> SyntaxVisitorContinueKind {
        scopeStack.append([])
        if let identifier = node.pattern.as(IdentifierPatternSyntax.self) {
            let name = identifier.identifier.text
            checkShadow(name: name, node: Syntax(node.pattern), severity: .error)
            registerInCurrentScope(name)
        }
        return .visitChildren
    }

    override func visitPost(_ node: ForStmtSyntax) {
        _ = scopeStack.popLast()
    }

    // MARK: - Variable Declarations

    override func visit(_ node: VariableDeclSyntax) -> SyntaxVisitorContinueKind {
        guard pattern.name == .variableShadowing else { return .visitChildren }

        for binding in node.bindings {
            guard let identifier = binding.pattern.as(IdentifierPatternSyntax.self) else { continue }
            let name = identifier.identifier.text

            // Skip `_` placeholder names
            guard name != "_" else { continue }

            // Check if this binding is inside an idiomatic optional unwrap
            if isIdiomaticOptionalBinding(identifier: identifier, binding: binding) {
                registerInCurrentScope(name)
                continue
            }

            let severity: IssueSeverity = initializerReferences(name: name, in: binding) ? .warning : .error
            checkShadow(name: name, node: Syntax(binding.pattern), severity: severity)
            registerInCurrentScope(name)
        }
        return .visitChildren
    }

    // MARK: - Function Parameters

    override func visit(_ node: FunctionDeclSyntax) -> SyntaxVisitorContinueKind {
        guard pattern.name == .variableShadowing else { return .visitChildren }

        for parameter in node.signature.parameterClause.parameters {
            let name = parameter.secondName?.text ?? parameter.firstName.text
            guard name != "_" else { continue }
            checkShadowAllFrames(name: name, node: Syntax(parameter), severity: .error)
        }
        return .visitChildren
    }

    // MARK: - Private Helpers

    private func registerClosureParameters(_ signature: ClosureSignatureSyntax) {
        guard pattern.name == .variableShadowing else { return }

        if let parameterClause = signature.parameterClause {
            switch parameterClause {
            case .parameterClause(let clause):
                for parameter in clause.parameters {
                    let name = parameter.secondName?.text ?? parameter.firstName.text
                    guard name != "_" else { continue }
                    checkShadow(name: name, node: Syntax(parameter), severity: .error)
                    registerInCurrentScope(name)
                }
            case .simpleInput(let list):
                for parameter in list {
                    let name = parameter.name.text
                    guard name != "_" else { continue }
                    checkShadow(name: name, node: Syntax(parameter), severity: .error)
                    registerInCurrentScope(name)
                }
            }
        }
    }

    private func registerInCurrentScope(_ name: String) {
        guard scopeStack.isEmpty == false else { return }
        scopeStack[scopeStack.count - 1].append(name)
    }

    /// Check all frames including the current one. Used for function parameters
    /// which are visited before the function body's CodeBlock pushes a new scope.
    private func checkShadowAllFrames(name: String, node: Syntax, severity: IssueSeverity) {
        for frame in scopeStack where frame.contains(name) {
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
        for frame in outerFrames where frame.contains(name) {
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

    /// Returns `true` when the binding's initializer contains a reference to `name`.
    /// Used to distinguish ambiguous shadows (e.g. `let config = config.cleaned()`)
    /// from clear-cut ones (e.g. `let config = 42`).
    private func initializerReferences(name: String, in binding: PatternBindingSyntax) -> Bool {
        guard let initializer = binding.initializer else { return false }
        return initializer.value.tokens(viewMode: .sourceAccurate).contains { token in
            token.tokenKind == .identifier(name)
        }
    }

    /// Returns `true` when the binding is an idiomatic optional unwrap:
    /// - `if let x = x` or `guard let x = x` (initializer references same name)
    /// - `if let x` or `guard let x` (Swift 5.7+ shorthand — no initializer)
    private func isIdiomaticOptionalBinding(
        identifier: IdentifierPatternSyntax,
        binding: PatternBindingSyntax
    ) -> Bool {
        // Walk up to find if we're inside an OptionalBindingConditionSyntax
        var current: Syntax? = Syntax(binding)
        while let parent = current?.parent {
            if let optionalBinding = parent.as(OptionalBindingConditionSyntax.self) {
                return isIdiomaticUnwrap(optionalBinding, boundName: identifier.identifier.text)
            }
            // Stop searching if we've left the condition list
            if parent.is(CodeBlockSyntax.self) || parent.is(CodeBlockItemListSyntax.self) {
                break
            }
            current = parent
        }
        return false
    }

    private func isIdiomaticUnwrap(
        _ optionalBinding: OptionalBindingConditionSyntax,
        boundName: String
    ) -> Bool {
        // Swift 5.7+ shorthand: `if let x` / `guard let x` — no initializer
        guard let initializer = optionalBinding.initializer else {
            return true
        }

        // `if let x = x` / `guard let x = x` — initializer is a bare reference to same name
        if let declRef = initializer.value.as(DeclReferenceExprSyntax.self) {
            return declRef.baseName.text == boundName
        }

        // `if let x = x as? T` / `guard let x = x as? T` — conditional type cast binding
        if let asExpr = initializer.value.as(AsExprSyntax.self),
           asExpr.questionOrExclamationMark?.tokenKind == .postfixQuestionMark,
           let declRef = asExpr.expression.as(DeclReferenceExprSyntax.self) {
            return declRef.baseName.text == boundName
        }

        return false
    }
}
