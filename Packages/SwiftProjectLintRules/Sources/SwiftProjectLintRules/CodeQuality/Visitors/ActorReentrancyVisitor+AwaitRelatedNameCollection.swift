import SwiftProjectLintVisitors
import SwiftSyntax

extension ActorReentrancyVisitor {
    // MARK: - Await-Related Name Collection

    /// Collects names that appear as direct operands of `await` expressions, or as the
    /// sequence of a `for-in` whose body contains an `await`. These are "resource" names —
    /// the things the async work actually operates on — as opposed to sentinel/gate properties.
    func collectAwaitRelatedNames(in syntax: Syntax) -> Set<String> {
        var names: Set<String> = []
        collectAwaitRelatedNamesHelper(in: syntax, into: &names)
        return names
    }

    private func collectAwaitRelatedNamesHelper(in syntax: Syntax, into names: inout Set<String>) {
        if syntax.is(FunctionDeclSyntax.self) || syntax.is(ClosureExprSyntax.self) { return }

        if let awaitExpr = syntax.as(AwaitExprSyntax.self) {
            // Collect all identifier names referenced directly inside this await expression
            collectDeclRefNames(in: Syntax(awaitExpr.expression), into: &names)
            return // Don't recurse further into this await
        }

        if let forIn = syntax.as(ForStmtSyntax.self) {
            // If the for-in body contains an await, the sequence variable is an await operand.
            // e.g. `for handler in handlers { try await handler(msg) }` → "handlers"
            if syntaxContainsAwait(Syntax(forIn.body)) {
                collectDeclRefNames(in: Syntax(forIn.sequence), into: &names)
            }
        }

        for child in syntax.children(viewMode: .sourceAccurate) {
            collectAwaitRelatedNamesHelper(in: child, into: &names)
        }
    }

    /// Collects the names reachable from `syntax` that can refer to a local or to one of the
    /// actor's own properties.
    ///
    /// A key-path component and a member of some other value are skipped: in
    /// `await send(jobs.map(\.isLoading))` the operand reads each job's `isLoading`, not the
    /// actor's, so it must not mark the actor's `isLoading` as a resource the await consumes. It
    /// used to, and the plain-condition filter then dropped a true `guard !isLoading` finding.
    private func collectDeclRefNames(in syntax: Syntax, into names: inout Set<String>) {
        if let declRef = syntax.as(DeclReferenceExprSyntax.self),
           declRef.isKeyPathComponentName == false,
           declRef.isMemberNameOfOtherBase == false {
            names.insert(declRef.baseName.text)
        }
        for child in syntax.children(viewMode: .sourceAccurate) {
            collectDeclRefNames(in: child, into: &names)
        }
    }

    /// Returns true if `syntax` contains an `AwaitExprSyntax` at any depth,
    /// without descending into nested functions or closures.
    func syntaxContainsAwait(_ syntax: Syntax) -> Bool {
        if syntax.is(AwaitExprSyntax.self) { return true }
        if syntax.is(FunctionDeclSyntax.self) || syntax.is(ClosureExprSyntax.self) { return false }
        return syntax.children(viewMode: .sourceAccurate).contains { syntaxContainsAwait($0) }
    }
}
