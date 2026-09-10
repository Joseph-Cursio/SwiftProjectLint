import SwiftSyntax

/// Collects the names of `typealias` declarations whose underlying type is a *function* type —
/// `typealias CommandRunner = @Sendable ([String]) async throws -> Data`.
///
/// Used as a project-wide pre-scan so `ConcreteTypeUsageVisitor` can tell a service class from
/// a closure. A property typed with one of these is already injected: a function value is the
/// seam, handed in at the call site and substituted in a test by writing another closure.
/// Asking for "a protocol abstraction" around it replaces a working seam with a heavier one
/// and buys nothing.
///
/// Only the alias is recorded, not the signature. Whether the closure is `@Sendable`, `async`
/// or throwing makes no difference to the question being asked.
///
/// ## A closure assignment is evidence too
///
/// The alias scan is project-wide, and "project" is the boundary it stops at. `CLIToolActor`'s
/// `CLIToolCommandRunner` is declared in **LintStudioUI**, a separate repository pulled in as a
/// package dependency, so two repositories that both bridge onto it each reported a finding the
/// prescan could not answer — recorded for two sweeps as *"a cross-package typealias the prescan
/// cannot see, a documented boundary rather than a defect"*.
///
/// It does not have to be a boundary, because the evidence is local:
///
/// ```swift
/// var bridgedRunner: CLIToolCommandRunner?
/// if let commandRunner {
///     bridgedRunner = { arguments, _ in … }        // ← only a function type accepts this
/// }
/// ```
///
/// **Assigning a closure literal to a binding proves its declared type is a function type.** The
/// compiler would reject it otherwise, so this is a fact rather than a heuristic, and it holds
/// whoever declares the alias and wherever they declare it.
///
/// Scoped to one function or initializer body: the declaration and the assignment must share an
/// enclosing body, so an unrelated `runner` elsewhere in the file cannot lend its name to a type
/// it has nothing to do with. A nested shadow inside the same body could still mislead, which is
/// the residual and is worth less than the boundary it removes.
public final class FunctionTypeAliasCollector: SyntaxVisitor, TypeCollectorProtocol {
    public var collectedTypes: Set<String> { aliasNames }

    private(set) var aliasNames: Set<String> = []

    public init() {
        super.init(viewMode: .sourceAccurate)
    }

    override public func visit(_ node: TypeAliasDeclSyntax) -> SyntaxVisitorContinueKind {
        if Self.resolvesToFunctionType(node.initializer.value) {
            aliasNames.insert(node.name.text)
        }
        return .visitChildren
    }

    override public func visit(_ node: FunctionDeclSyntax) -> SyntaxVisitorContinueKind {
        if let body = node.body { recordClosureAssignedTypes(in: Syntax(body)) }
        return .visitChildren
    }

    override public func visit(_ node: InitializerDeclSyntax) -> SyntaxVisitorContinueKind {
        if let body = node.body { recordClosureAssignedTypes(in: Syntax(body)) }
        return .visitChildren
    }

    /// Records every declared type that a closure literal is assigned to somewhere in `body`.
    ///
    /// Two shapes, because an optional binding is usually declared and filled in separate
    /// statements: `let x: T = { … }` states it outright, and `var x: T?` followed by
    /// `x = { … }` states it across two. The second is the one the corpus contains.
    private func recordClosureAssignedTypes(in body: Syntax) {
        var declaredType: [String: String] = [:]
        collectAnnotatedBindings(in: body, into: &declaredType)
        guard !declaredType.isEmpty else { return }
        for name in closureAssignedNames(in: body) {
            if let typeName = declaredType[name] { aliasNames.insert(typeName) }
        }
    }

    /// Local bindings carrying a nominal type annotation, with the optional unwrapped — and the
    /// ones already initialised with a closure recorded on the spot.
    private func collectAnnotatedBindings(in node: Syntax, into found: inout [String: String]) {
        for child in node.children(viewMode: .sourceAccurate) {
            if let variable = child.as(VariableDeclSyntax.self) {
                for binding in variable.bindings {
                    guard let name = binding.pattern.as(IdentifierPatternSyntax.self)?.identifier.text,
                          let annotation = binding.typeAnnotation?.type,
                          let typeName = Self.nominalName(of: annotation) else { continue }
                    found[name] = typeName
                    if let value = binding.initializer?.value, Self.isClosure(value) {
                        aliasNames.insert(typeName)
                    }
                }
            }
            collectAnnotatedBindings(in: child, into: &found)
        }
    }

    /// Names on the left of an `=` whose right-hand side is a closure literal.
    ///
    /// `SwiftParser` leaves an assignment unfolded as a `SequenceExprSyntax` of
    /// `target`, `=`, `value`, so the three are read off the element list rather than from an
    /// `InfixOperatorExprSyntax` — the same reason the `??` walk elsewhere handles both spellings.
    private func closureAssignedNames(in node: Syntax) -> Set<String> {
        var found: Set<String> = []
        collectClosureAssignedNames(in: node, into: &found)
        return found
    }

    private func collectClosureAssignedNames(in node: Syntax, into found: inout Set<String>) {
        for child in node.children(viewMode: .sourceAccurate) {
            if let sequence = child.as(SequenceExprSyntax.self) {
                let elements = Array(sequence.elements)
                for index in elements.indices.dropFirst().dropLast()
                where elements[index].as(AssignmentExprSyntax.self) != nil {
                    if let target = elements[index - 1].as(DeclReferenceExprSyntax.self),
                       Self.isClosure(elements[index + 1]) {
                        found.insert(target.baseName.text)
                    }
                }
            }
            if let infix = child.as(InfixOperatorExprSyntax.self),
               infix.operator.is(AssignmentExprSyntax.self),
               let target = infix.leftOperand.as(DeclReferenceExprSyntax.self),
               Self.isClosure(infix.rightOperand) {
                found.insert(target.baseName.text)
            }
            collectClosureAssignedNames(in: child, into: &found)
        }
    }

    /// A closure literal, seeing through the wrappers an assignment may carry.
    private static func isClosure(_ expression: ExprSyntax) -> Bool {
        if expression.is(ClosureExprSyntax.self) { return true }
        if let tuple = expression.as(TupleExprSyntax.self), tuple.elements.count == 1,
           let only = tuple.elements.first {
            return isClosure(only.expression)
        }
        return false
    }

    /// The base name of a nominal type annotation, with one level of optional unwrapped.
    /// `CLIToolCommandRunner?` is the spelling a bridged seam uses, and an annotation that is
    /// *already* a function type needs no evidence — the existing alias path or the declaration
    /// itself covers it.
    private static func nominalName(of type: TypeSyntax) -> String? {
        if let optional = type.as(OptionalTypeSyntax.self) {
            return nominalName(of: optional.wrappedType)
        }
        return type.as(IdentifierTypeSyntax.self)?.name.text
    }

    /// Whether `type` is a function type, seeing through the wrappers an alias commonly uses.
    ///
    /// `@Sendable (Int) -> Void` arrives as an `AttributedTypeSyntax`, and a parenthesised
    /// signature — the form an optional alias needs — as a `TupleTypeSyntax` of one element.
    private static func resolvesToFunctionType(_ type: TypeSyntax) -> Bool {
        if type.is(FunctionTypeSyntax.self) { return true }
        if let attributed = type.as(AttributedTypeSyntax.self) {
            return resolvesToFunctionType(attributed.baseType)
        }
        if let tuple = type.as(TupleTypeSyntax.self), tuple.elements.count == 1,
           let only = tuple.elements.first {
            return resolvesToFunctionType(only.type)
        }
        return false
    }
}
