import SwiftSyntax

/// Collects the names of underscore-prefixed members the project itself declares.
///
/// `AccessingImplementationDetailsVisitor` reads a leading underscore as "implementation
/// detail", which is the right heuristic across a module boundary and wrong inside one. Within
/// a module there is no public interface to reach past: `_value` on another instance of a type
/// this same module declares is a module using its own convention, exactly as `self._value` is.
///
/// The visitor already exempts `self`, `super`, an underscored base, `@_spi` members, and
/// members the *enclosing type* declares. That last exemption is the same idea stopping one
/// scope too early — it catches `other._value` inside the declaring type and misses it inside a
/// sibling type in the same module.
///
/// Measured on 1.78 million lines of Apple, swiftlang and Swift server workgroup code, this rule
/// reported **5,600** findings at 3.14 per 1,000 lines against 0.01 in this corpus — a 300×
/// gap that is a difference of idiom, not of quality. The standard library uses the underscore
/// convention for members that must be `public` to be `@inlinable` while remaining internal by
/// intent; `swift-atomics` alone produced 927 findings, giving it the highest reported density
/// of any repository this tool has scanned.
///
/// Only declarations are collected, so a *use* of a name the project never declares — genuinely
/// reaching into a dependency's internals — is still reported.
public final class UnderscoredMemberCollector: SyntaxVisitor, TypeCollectorProtocol {
    public var collectedTypes: Set<String> { memberNames }

    private(set) var memberNames: Set<String> = []

    public init() {
        super.init(viewMode: .sourceAccurate)
    }

    override public func visit(_ node: FunctionDeclSyntax) -> SyntaxVisitorContinueKind {
        insertIfUnderscored(node.name.text)
        return .visitChildren
    }

    override public func visit(_ node: VariableDeclSyntax) -> SyntaxVisitorContinueKind {
        for binding in node.bindings {
            if let identifier = binding.pattern.as(IdentifierPatternSyntax.self) {
                insertIfUnderscored(identifier.identifier.text)
            }
        }
        return .visitChildren
    }

    override public func visit(_ node: EnumCaseElementSyntax) -> SyntaxVisitorContinueKind {
        insertIfUnderscored(node.name.text)
        return .visitChildren
    }

    private func insertIfUnderscored(_ name: String) {
        guard name.hasPrefix("_") else { return }
        memberNames.insert(name)
    }
}
