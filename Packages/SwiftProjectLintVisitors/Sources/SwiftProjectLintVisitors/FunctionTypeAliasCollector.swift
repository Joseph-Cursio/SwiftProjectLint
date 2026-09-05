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
