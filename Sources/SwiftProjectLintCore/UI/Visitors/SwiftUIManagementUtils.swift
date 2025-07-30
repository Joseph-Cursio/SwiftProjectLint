// SwiftUIManagementUtils.swift
// Utility methods for SwiftUIManagementVisitor
import SwiftSyntax

extension SwiftUIManagementVisitor {
    // Utility to check if a struct conforms to the View protocol
    func isSwiftUIView(_ node: StructDeclSyntax) -> Bool {
        for inheritance in node.inheritanceClause?.inheritedTypes ?? [] {
            if inheritance.type.as(IdentifierTypeSyntax.self)?.name.text == "View" {
                return true
            }
        }
        return false
    }

    // Extract property wrapper from variable declaration
    func extractPropertyWrapper(from node: VariableDeclSyntax) -> PropertyWrapper? {
        for attribute in node.attributes {
            if let attributeSyntax = attribute.as(AttributeSyntax.self),
               let attributeName = attributeSyntax.attributeName.as(IdentifierTypeSyntax.self),
               let wrapper = PropertyWrapper(rawValue: attributeName.name.text) {
                return wrapper
            }
        }
        return nil
    }

    // Extract type annotation from pattern binding
    func extractTypeAnnotation(from binding: PatternBindingSyntax) -> String {
        if let typeAnnotation = binding.typeAnnotation {
            return typeAnnotation.type.description.trimmingCharacters(in: .whitespaces)
        }
        return ""
    }

    // Count state variables in a struct
    func countStateVariables(in node: StructDeclSyntax) -> Int {
        var count = 0
        for member in node.memberBlock.members {
            if let variableDecl = member.decl.as(VariableDeclSyntax.self) {
                guard let propertyWrapper = extractPropertyWrapper(from: variableDecl) else { continue }
                if propertyWrapper == .state || propertyWrapper == .stateObject {
                    count += variableDecl.bindings.count
                }
            }
        }
        return count
    }
    
    func getLineNumber(for node: StructDeclSyntax) -> Int {
        guard let converter = sourceLocationConverter else { return 1 }
        let position = node.positionAfterSkippingLeadingTrivia
        let location = converter.location(for: position)
        return location.line
    }
    
    func getLineNumber(for node: VariableDeclSyntax) -> Int {
        guard let converter = sourceLocationConverter else { return 1 }
        let position = node.positionAfterSkippingLeadingTrivia
        let location = converter.location(for: position)
        return location.line
    }
}
