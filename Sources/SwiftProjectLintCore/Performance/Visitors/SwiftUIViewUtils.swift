// Utility helpers related to identifying SwiftUI views
import SwiftSyntax

extension PerformanceVisitor {
    func isSwiftUIView(_ node: StructDeclSyntax) -> Bool {
        for inheritance in node.inheritanceClause?.inheritedTypes ?? [] {
            if inheritance.type.as(IdentifierTypeSyntax.self)?.name.text == "View" {
                return true
            }
        }
        return false
    }
}
