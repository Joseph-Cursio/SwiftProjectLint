import SwiftProjectLintModels
import SwiftProjectLintVisitors
import SwiftSyntax

extension ActorReentrancyVisitor {
    // MARK: - Await Detection

    func collectAwaitPositions(
        in syntax: Syntax,
        into results: inout [AbsolutePosition]
    ) {
        if syntax.is(FunctionDeclSyntax.self) || syntax.is(ClosureExprSyntax.self) {
            return
        }

        if syntax.is(AwaitExprSyntax.self) {
            results.append(syntax.position)
        }

        for child in syntax.children(viewMode: .sourceAccurate) {
            collectAwaitPositions(in: child, into: &results)
        }
    }
}
