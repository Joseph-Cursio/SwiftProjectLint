import SwiftSyntax

extension InitializerDeclSyntax {
    /// Direct accessor for the parameter list, avoiding deep signature navigation.
    public var parameterList: FunctionParameterListSyntax {
        signature.parameterClause.parameters
    }
}
