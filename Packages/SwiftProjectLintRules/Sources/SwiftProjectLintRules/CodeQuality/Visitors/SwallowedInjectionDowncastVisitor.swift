import SwiftProjectLintModels
import SwiftProjectLintRegistry
import SwiftProjectLintVisitors
import SwiftSyntax

/// Flags an initializer that takes a dependency through a protocol abstraction and then
/// downcasts that parameter to a concrete type with `as?` / `as!`.
///
/// This is the shape of a real injection bug: the API *advertises* that it accepts any
/// conforming type (so callers — and tests — can pass a mock), but the body quietly
/// requires one specific concrete type and discards anything else:
///
/// ```swift
/// init(cache: CacheManagerProtocol?) {
///     if let concrete = cache as? CacheManager { self.cache = concrete }
///     else { self.cache = CacheManager() }   // injected mock silently dropped
/// }
/// ```
///
/// The dependency-injection seam looks real but isn't — substituting a test double
/// compiles and runs, yet has no effect. The fix is to store the value through its
/// protocol type and honor whatever was passed.
///
/// **Detection.** Within an `init`, the visitor records parameters whose type is an
/// abstraction — `any P`, or a name ending in `Protocol` (optionals unwrapped). It then
/// flags any `as?` / `as!` whose operand is one of those parameters and whose target is
/// a *concrete* type (not itself a protocol / `any`, which would be legitimate
/// narrowing). Severity is `info`: occasionally the downcast is intentional, so this is
/// a review prompt, not a hard error.
final class SwallowedInjectionDowncastVisitor: BasePatternVisitor {

    private static let protocolSuffix = "Protocol"

    /// Stack of abstraction-typed parameter-name sets, one frame per enclosing `init`.
    private var initParamStack: [Set<String>] = []

    required init(pattern: SyntaxPattern, viewMode: SyntaxTreeViewMode = .sourceAccurate) {
        super.init(pattern: pattern, viewMode: viewMode)
    }

    override func visit(_ node: InitializerDeclSyntax) -> SyntaxVisitorContinueKind {
        initParamStack.append(abstractionParamNames(node))
        return .visitChildren
    }

    override func visitPost(_ _: InitializerDeclSyntax) {
        initParamStack.removeLast()
    }

    /// Unfolded form: the parser leaves `operand as? Type` as an
    /// `UnresolvedAsExprSyntax` sitting between its operand and type inside a
    /// `SequenceExprSyntax` (operator precedence isn't resolved without folding, which
    /// the linter doesn't run). The operand is the preceding element, the target the
    /// following `TypeExprSyntax`.
    override func visit(_ node: SequenceExprSyntax) -> SyntaxVisitorContinueKind {
        guard initParamStack.last != nil else { return .visitChildren }
        let elements = Array(node.elements)
        for (index, element) in elements.enumerated() {
            guard let cast = element.as(UnresolvedAsExprSyntax.self),
                  cast.questionOrExclamationMark != nil,           // as? / as! only
                  index > 0, index + 1 < elements.count,
                  let operand = elements[index - 1].as(DeclReferenceExprSyntax.self),
                  let typeExpr = elements[index + 1].as(TypeExprSyntax.self)
            else { continue }
            flagIfSwallowed(operand: operand, targetType: typeExpr.type, at: Syntax(cast))
        }
        return .visitChildren
    }

    /// Folded form: present only if some caller runs `SwiftOperators` folding before the
    /// walk. Harmless to keep — it makes the rule robust to that configuration.
    override func visit(_ node: AsExprSyntax) -> SyntaxVisitorContinueKind {
        guard node.questionOrExclamationMark != nil,
              let operand = node.expression.as(DeclReferenceExprSyntax.self)
        else { return .visitChildren }
        flagIfSwallowed(operand: operand, targetType: node.type, at: Syntax(node))
        return .visitChildren
    }

    /// Flags when `operand` is an abstraction-typed init parameter and `targetType` is a
    /// concrete type (not a protocol / `any`, which would be legitimate narrowing).
    private func flagIfSwallowed(
        operand: DeclReferenceExprSyntax,
        targetType: TypeSyntax,
        at node: Syntax
    ) {
        guard let abstractionParams = initParamStack.last,
              abstractionParams.contains(operand.baseName.text),
              !isAbstractionType(targetType)
        else { return }

        let paramName = operand.baseName.text
        let targetName = targetType.trimmedDescription
        addIssue(
            severity: .info,
            message: "Initializer downcasts injected '\(paramName)' to concrete "
                + "'\(targetName)' — the protocol parameter accepts any conformer, but this "
                + "honors only one type and silently drops the rest (e.g. test doubles)",
            filePath: getFilePath(for: node),
            lineNumber: getLineNumber(for: node),
            suggestion: "Store '\(paramName)' through its protocol type and use the injected "
                + "value directly, instead of downcasting to '\(targetName)'.",
            ruleName: .swallowedInjectionDowncast
        )
    }

    /// Parameter names whose declared type is an abstraction (`any P` or `…Protocol`),
    /// using the internal (second) name the body references.
    private func abstractionParamNames(_ initDecl: InitializerDeclSyntax) -> Set<String> {
        var names: Set<String> = []
        for parameter in initDecl.signature.parameterClause.parameters
        where isAbstractionType(parameter.type) {
            names.insert((parameter.secondName ?? parameter.firstName).text)
        }
        return names
    }

    /// True when `type`, after unwrapping `Optional` / IUO and parentheses, is an
    /// existential (`any P`) or a nominal type whose name ends in `Protocol`.
    private func isAbstractionType(_ type: TypeSyntax) -> Bool {
        let unwrapped = unwrap(type)
        if unwrapped.is(SomeOrAnyTypeSyntax.self) {
            // `any P` / `some P` — treat the existential form as an abstraction.
            return unwrapped.as(SomeOrAnyTypeSyntax.self)?.someOrAnySpecifier.text == "any"
        }
        if let identifier = unwrapped.as(IdentifierTypeSyntax.self) {
            return identifier.name.text.hasSuffix(Self.protocolSuffix)
        }
        return false
    }

    /// Strips `Optional` (`T?`), implicitly-unwrapped optionals (`T!`), and tuple
    /// parentheses (`(any P)?` → `any P`) down to the underlying type.
    private func unwrap(_ type: TypeSyntax) -> TypeSyntax {
        if let optional = type.as(OptionalTypeSyntax.self) {
            return unwrap(optional.wrappedType)
        }
        if let iuo = type.as(ImplicitlyUnwrappedOptionalTypeSyntax.self) {
            return unwrap(iuo.wrappedType)
        }
        if let tuple = type.as(TupleTypeSyntax.self),
           tuple.elements.count == 1,
           let only = tuple.elements.first {
            return unwrap(only.type)
        }
        return type
    }
}
