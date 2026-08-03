import SwiftProjectLintModels
import SwiftSyntax
/// Whether a test could actually call this declaration.
///
/// `@testable import` raises `internal` to visible and stops there. `private` and `fileprivate` are
/// beyond it, and so is anything — however open — nested inside a `private` type, because narrowing
/// a type hides its members just as effectively as marking each one.
///
/// This predicate already existed as *prose* in this file's own doc comment and in
/// `couldBePrivate` / `couldBePrivateMember`, which exist precisely to stop a scope rule advising a
/// reader into an untestable corner. It was never applied to the linter's own seeding, and the
/// measurement was stark: **316 of 468 seeds marked analysable named a function no test could
/// reach.** `swift-infer` had been declining them all along under its `RestrictedFunction` concept;
/// the two tools simply had no vocabulary in which to notice they disagreed.
extension PropertyTestCandidacy {

    /// Access-level keywords that put a declaration beyond `@testable import`.
    public static let unreachableModifiers: Set<String> = ["private", "fileprivate"]

    /// `false` when this declaration, or any type enclosing it, is `private` or `fileprivate`.
    public static func isTestReachable(_ node: some SyntaxProtocol) -> Bool {
        restriction(of: node) == nil
    }

    /// **What** would have to move for a test to reach this declaration, or `nil` when nothing does.
    ///
    /// The enclosing-type check runs **last but wins**, and the order is the point. A `private` func
    /// inside a `private` struct is restricted both ways, and only the outer one is binding: widen
    /// the func and it is still unreachable. Reporting `.declaration` there would send a patch
    /// generator to change a keyword that alters nothing — see `TestRestriction`.
    public static func restriction(of node: some SyntaxProtocol) -> TestRestriction? {
        if !enclosingTypesAreReachable(node) { return .enclosingType }
        if let declaration = node.as(DeclSyntax.self) ?? node.parent?.as(DeclSyntax.self),
           hasUnreachableModifier(declaration) {
            return .declaration
        }
        if let function = node.as(FunctionDeclSyntax.self), isUnreachable(function.modifiers) {
            return .declaration
        }
        if let property = node.as(VariableDeclSyntax.self), isUnreachable(property.modifiers) {
            return .declaration
        }
        return nil
    }

    /// A `private struct`'s `internal` members are unreachable too — the container decides.
    private static func enclosingTypesAreReachable(_ node: some SyntaxProtocol) -> Bool {
        var current: Syntax? = Syntax(node).parent
        while let ancestor = current {
            if let modifiers = typeModifiers(of: ancestor), isUnreachable(modifiers) {
                return false
            }
            current = ancestor.parent
        }
        return true
    }

    private static func typeModifiers(of node: Syntax) -> DeclModifierListSyntax? {
        if let structure = node.as(StructDeclSyntax.self) { return structure.modifiers }
        if let object = node.as(ClassDeclSyntax.self) { return object.modifiers }
        if let enumeration = node.as(EnumDeclSyntax.self) { return enumeration.modifiers }
        if let actorDecl = node.as(ActorDeclSyntax.self) { return actorDecl.modifiers }
        if let extensionDecl = node.as(ExtensionDeclSyntax.self) { return extensionDecl.modifiers }
        return nil
    }

    private static func hasUnreachableModifier(_ declaration: DeclSyntax) -> Bool {
        if let function = declaration.as(FunctionDeclSyntax.self) { return isUnreachable(function.modifiers) }
        if let property = declaration.as(VariableDeclSyntax.self) { return isUnreachable(property.modifiers) }
        return false
    }

    private static func isUnreachable(_ modifiers: DeclModifierListSyntax) -> Bool {
        modifiers.contains { unreachableModifiers.contains($0.name.text) }
    }
}
