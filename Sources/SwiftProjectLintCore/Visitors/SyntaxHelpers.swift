import SwiftSyntax

/// Returns whether the given struct declaration conforms to SwiftUI's `View` or `App` protocol.
func isSwiftUIView(_ node: StructDeclSyntax) -> Bool {
    let swiftUITypes: Set<String> = [SwiftUIProtocol.view.rawValue, SwiftUIProtocol.app.rawValue]
    for inheritance in node.inheritanceClause?.inheritedTypes ?? [] {
        if let name = inheritance.type.as(IdentifierTypeSyntax.self)?.name.text,
           swiftUITypes.contains(name) {
            return true
        }
    }
    return false
}
