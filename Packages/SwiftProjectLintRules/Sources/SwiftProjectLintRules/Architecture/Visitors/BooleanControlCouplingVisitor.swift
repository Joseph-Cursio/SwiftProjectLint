import Foundation
import SwiftProjectLintModels
import SwiftProjectLintRegistry
import SwiftProjectLintVisitors
import SwiftSyntax

/// Detects a `Bool` parameter that the function body uses to choose between two
/// *substantial* code paths — Adam Tornhill's "control coupling" smell. The
/// caller is reaching in to select which behavior the callee runs, a hidden
/// design decision better expressed as a strategy (two named functions, or a
/// protocol / closure passed in) so each path is named and discoverable.
///
/// Distinct from `MagicBooleanParameterVisitor`, which flags unlabeled boolean
/// *arguments* at call sites (a caller-side readability smell). This rule is
/// callee-side: it fires only when the parameter actually drives an `if`/`else`
/// with two non-trivial arms. Swift's argument labels already make the call site
/// readable, so the value here is in the *body*, not the call.
final class BooleanControlCouplingVisitor: BasePatternVisitor {

    /// The set of `Bool` parameter names in scope for each enclosing function /
    /// initializer, innermost last. Empty for overrides, bodyless declarations,
    /// and functions with no boolean parameters — so an `if` in those scopes
    /// never matches.
    private var boolParamStack: [Set<String>] = []

    required init(pattern: SyntaxPattern, viewMode: SyntaxTreeViewMode = .sourceAccurate) {
        super.init(pattern: pattern, viewMode: viewMode)
    }

    // MARK: - Function / initializer context

    override func visit(_ node: FunctionDeclSyntax) -> SyntaxVisitorContinueKind {
        boolParamStack.append(
            scopedBoolParams(node.signature.parameterClause, modifiers: node.modifiers, hasBody: node.body != nil)
        )
        return .visitChildren
    }

    override func visitPost(_: FunctionDeclSyntax) {
        boolParamStack.removeLast()
    }

    override func visit(_ node: InitializerDeclSyntax) -> SyntaxVisitorContinueKind {
        boolParamStack.append(
            scopedBoolParams(node.signature.parameterClause, modifiers: node.modifiers, hasBody: node.body != nil)
        )
        return .visitChildren
    }

    override func visitPost(_: InitializerDeclSyntax) {
        boolParamStack.removeLast()
    }

    // MARK: - Branch detection

    override func visit(_ node: IfExprSyntax) -> SyntaxVisitorContinueKind {
        // Require: not a test/fixture file, a boolean parameter in scope, and a
        // plain `else { … }` block (an `else if` chain is handled when its own
        // inner `if` is visited).
        guard isTestOrFixtureFile() == false,
              let params = boolParamStack.last, params.isEmpty == false,
              let elseBody = node.elseBody?.as(CodeBlockSyntax.self) else {
            return .visitChildren
        }

        // The condition must reference one of the boolean parameters directly
        // (not an `obj.flag` that merely shares the name).
        guard let paramName = referencedParameter(in: Syntax(node.conditions), names: params) else {
            return .visitChildren
        }

        // Both arms must be substantial — this is what separates "two strategies"
        // from "optional embellishment" (`if verbose { log() }`).
        guard isSubstantialArm(node.body), isSubstantialArm(elseBody) else {
            return .visitChildren
        }

        addIssue(
            severity: .warning,
            message: "Boolean parameter '\(paramName)' selects between two code paths — "
                + "this is control coupling (the caller decides which behavior runs).",
            filePath: getFilePath(for: Syntax(node)),
            lineNumber: getLineNumber(for: Syntax(node)),
            suggestion: "Replace the flag with a strategy: split into two named functions, "
                + "or pass in a protocol / closure so each path is explicit and named.",
            ruleName: .booleanControlCoupling
        )
        return .visitChildren
    }

    // MARK: - Helpers

    /// Boolean parameter internal names for a function/initializer, or an empty
    /// set when the declaration can't (or shouldn't) be analyzed — no body, an
    /// `override` (the signature is inherited and can't be changed freely), or
    /// no boolean parameters.
    private func scopedBoolParams(
        _ clause: FunctionParameterClauseSyntax,
        modifiers: DeclModifierListSyntax,
        hasBody: Bool
    ) -> Set<String> {
        guard hasBody,
              modifiers.contains(where: { $0.name.tokenKind == .keyword(.override) }) == false else {
            return []
        }
        var names: Set<String> = []
        for param in clause.parameters where isBoolType(param.type) {
            // The internal (body-visible) name is the second name when present
            // (`func f(animated flag: Bool)` → `flag`), else the first.
            let internalName = (param.secondName ?? param.firstName).text
            if internalName != "_" {
                names.insert(internalName)
            }
        }
        return names
    }

    private func isBoolType(_ type: TypeSyntax) -> Bool {
        if type.as(IdentifierTypeSyntax.self)?.name.text == "Bool" {
            return true
        }
        if let optional = type.as(OptionalTypeSyntax.self),
           optional.wrappedType.as(IdentifierTypeSyntax.self)?.name.text == "Bool" {
            return true
        }
        return false
    }

    /// Returns the name of a parameter referenced as a value inside `node`,
    /// ignoring identifiers that are the member half of an `obj.member` access
    /// (so `config.flag` does not match a parameter named `flag`).
    private func referencedParameter(in node: Syntax, names: Set<String>) -> String? {
        if let ref = node.as(DeclReferenceExprSyntax.self), names.contains(ref.baseName.text) {
            let isMemberRHS = node.parent?.as(MemberAccessExprSyntax.self)?.declName == ref
            if isMemberRHS == false {
                return ref.baseName.text
            }
        }
        for child in node.children(viewMode: .sourceAccurate) {
            if let found = referencedParameter(in: child, names: names) {
                return found
            }
        }
        return nil
    }

    /// An arm is "substantial" — i.e. real work, not a trivial value selection —
    /// when it has two or more statements, or contains a function/method call.
    /// This deliberately treats single literal/value returns (`return .red`,
    /// `return 0`) as *not* substantial: a boolean→value map is not the
    /// control-coupling smell this rule targets.
    private func isSubstantialArm(_ block: CodeBlockSyntax) -> Bool {
        if block.statements.count >= 2 {
            return true
        }
        return containsCall(Syntax(block.statements))
    }

    private func containsCall(_ node: Syntax) -> Bool {
        if node.is(FunctionCallExprSyntax.self) {
            return true
        }
        for child in node.children(viewMode: .sourceAccurate) where containsCall(child) {
            return true
        }
        return false
    }
}
