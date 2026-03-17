import SwiftSyntax

/// Returns whether the given struct declaration conforms to the SwiftUI `View` protocol.
func isSwiftUIView(_ node: StructDeclSyntax) -> Bool {
    for inheritance in node.inheritanceClause?.inheritedTypes ?? []
        where inheritance.type.as(IdentifierTypeSyntax.self)?.name.text == SwiftUIProtocol.view.rawValue {
        return true
    }
    return false
}
