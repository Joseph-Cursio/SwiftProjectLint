import SwiftSyntax

public extension InitializerDeclSyntax {
    /// Direct accessor for the parameter list, avoiding deep signature navigation.
    var parameterList: FunctionParameterListSyntax {
        signature.parameterClause.parameters
    }
}
