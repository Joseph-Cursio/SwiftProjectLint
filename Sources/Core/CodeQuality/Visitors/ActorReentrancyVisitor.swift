import SwiftSyntax

/// A SwiftSyntax visitor that detects actor reentrancy risks.
///
/// Flags async functions inside actors where a stored property is checked in a guard/if
/// condition but not updated before an `await`, allowing concurrent callers to pass
/// the same guard and trigger duplicate work.
///
/// ## False-positive suppression
/// Optional-binding conditions (`guard let x = prop`) are only flagged when the bound
/// name is NOT used as a direct operand of an `await` expression (or as the sequence of
/// a `for-in` whose body contains `await`). Resource guards of the form
/// `guard let connection = connection else { throw }` are therefore suppressed, because
/// `connection` (the bound name) is the receiver of the subsequent `await connection.send(…)`.
/// Scheduling sentinels of the form `if let lastRun = lastRunDate { … await work() }` are
/// still flagged, because `lastRun` does not appear in the `await` operand.
final class ActorReentrancyVisitor: BasePatternVisitor {

    required init(pattern: SyntaxPattern, viewMode: SyntaxTreeViewMode = .sourceAccurate) {
        super.init(pattern: pattern, viewMode: viewMode)
    }

    override func visit(_ node: ActorDeclSyntax) -> SyntaxVisitorContinueKind {
        guard pattern.name == .actorReentrancy else { return .visitChildren }
        analyzeActor(node)
        return .skipChildren
    }

    // MARK: - Actor Analysis

    private func analyzeActor(_ actor: ActorDeclSyntax) {
        let storedVarNames = collectStoredVarNames(from: actor)
        guard !storedVarNames.isEmpty else { return }

        for member in actor.memberBlock.members {
            guard let funcDecl = member.decl.as(FunctionDeclSyntax.self),
                  funcDecl.signature.effectSpecifiers?.asyncSpecifier != nil,
                  let body = funcDecl.body else { continue }

            analyzeAsyncFunction(funcDecl: funcDecl, body: body, storedVarNames: storedVarNames)
        }
    }

    private func collectStoredVarNames(from actor: ActorDeclSyntax) -> Set<String> {
        var names: Set<String> = []
        for member in actor.memberBlock.members {
            guard let varDecl = member.decl.as(VariableDeclSyntax.self),
                  varDecl.bindingSpecifier.text == "var" else { continue }
            for binding in varDecl.bindings {
                // Skip computed properties (those with accessor blocks)
                if binding.accessorBlock != nil { continue }
                if let identifier = binding.pattern.as(IdentifierPatternSyntax.self) {
                    names.insert(identifier.identifier.text)
                }
            }
        }
        return names
    }

    // MARK: - Async Function Analysis

    private func analyzeAsyncFunction(
        funcDecl: FunctionDeclSyntax,
        body: CodeBlockSyntax,
        storedVarNames: Set<String>
    ) {
        let bodySyntax = Syntax(body)

        // Pre-compute names bound in optional bindings that are used as await operands.
        // These are resource guards, not scheduling sentinels, and should not be flagged.
        let awaitRelatedNames = collectAwaitRelatedNames(in: bodySyntax)

        // 1. Collect property references from guard/if conditions
        var propertyChecks: [(name: String, position: AbsolutePosition)] = []
        collectPropertyChecksFromConditions(
            in: bodySyntax,
            storedVarNames: storedVarNames,
            awaitRelatedNames: awaitRelatedNames,
            into: &propertyChecks
        )
        guard !propertyChecks.isEmpty else { return }

        let checkedNames = Set(propertyChecks.map(\.name))

        // 2. Collect assignments to those properties
        var assignments: [(name: String, position: AbsolutePosition)] = []
        collectAssignments(in: bodySyntax, propertyNames: checkedNames, into: &assignments)

        // 3. Collect await positions
        var awaitPositions: [AbsolutePosition] = []
        collectAwaitPositions(in: bodySyntax, into: &awaitPositions)
        guard !awaitPositions.isEmpty else { return }

        // 4. For each checked property, see if any await follows without an intervening assignment
        var unprotected: Set<String> = []
        for check in propertyChecks {
            for awaitPos in awaitPositions where awaitPos > check.position {
                let hasAssignment = assignments.contains { assignment in
                    assignment.name == check.name
                        && assignment.position > check.position
                        && assignment.position < awaitPos
                }
                if !hasAssignment {
                    unprotected.insert(check.name)
                    break
                }
            }
        }

        guard !unprotected.isEmpty else { return }

        let propList = unprotected.sorted().joined(separator: ", ")
        let funcName = funcDecl.name.text
        addIssue(
            severity: .warning,
            message: "Actor reentrancy risk in '\(funcName)': '\(propList)' is checked "
                + "before await but not updated, allowing concurrent callers "
                + "to pass the same guard.",
            filePath: getFilePath(for: Syntax(funcDecl)),
            lineNumber: getLineNumber(for: Syntax(funcDecl)),
            suggestion: "Set '\(propList)' eagerly before the await to prevent "
                + "duplicate invocations.",
            ruleName: .actorReentrancy
        )
    }

    // MARK: - Await-Related Name Collection

    /// Collects names that appear as direct operands of `await` expressions, or as the
    /// sequence of a `for-in` whose body contains an `await`. These are "resource" names —
    /// the things the async work actually operates on — as opposed to sentinel/gate properties.
    private func collectAwaitRelatedNames(in syntax: Syntax) -> Set<String> {
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

        if let forIn = syntax.as(ForInStmtSyntax.self) {
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

    /// Collects all `DeclReferenceExprSyntax` base names reachable from `syntax`.
    private func collectDeclRefNames(in syntax: Syntax, into names: inout Set<String>) {
        if let declRef = syntax.as(DeclReferenceExprSyntax.self) {
            names.insert(declRef.baseName.text)
        }
        for child in syntax.children(viewMode: .sourceAccurate) {
            collectDeclRefNames(in: child, into: &names)
        }
    }

    /// Returns true if `syntax` contains an `AwaitExprSyntax` at any depth,
    /// without descending into nested functions or closures.
    private func syntaxContainsAwait(_ syntax: Syntax) -> Bool {
        if syntax.is(AwaitExprSyntax.self) { return true }
        if syntax.is(FunctionDeclSyntax.self) || syntax.is(ClosureExprSyntax.self) { return false }
        return syntax.children(viewMode: .sourceAccurate).contains { syntaxContainsAwait($0) }
    }

    // MARK: - Condition Property Checks

    private func collectPropertyChecksFromConditions(
        in syntax: Syntax,
        storedVarNames: Set<String>,
        awaitRelatedNames: Set<String>,
        into results: inout [(name: String, position: AbsolutePosition)]
    ) {
        // Don't descend into nested functions or closures
        if syntax.is(FunctionDeclSyntax.self) || syntax.is(ClosureExprSyntax.self) {
            return
        }

        if let guardStmt = syntax.as(GuardStmtSyntax.self) {
            let refs = propertyRefsInConditionList(
                guardStmt.conditions,
                matching: storedVarNames,
                awaitRelatedNames: awaitRelatedNames
            )
            for ref in refs {
                results.append((ref, guardStmt.position))
            }
        } else if let ifExpr = syntax.as(IfExprSyntax.self) {
            let refs = propertyRefsInConditionList(
                ifExpr.conditions,
                matching: storedVarNames,
                awaitRelatedNames: awaitRelatedNames
            )
            for ref in refs {
                results.append((ref, ifExpr.position))
            }
        }

        for child in syntax.children(viewMode: .sourceAccurate) {
            collectPropertyChecksFromConditions(
                in: child,
                storedVarNames: storedVarNames,
                awaitRelatedNames: awaitRelatedNames,
                into: &results
            )
        }
    }

    /// Iterates a condition list and returns the stored-property names that are genuine
    /// scheduling gates. Optional-binding conditions whose bound name appears in
    /// `awaitRelatedNames` are treated as resource guards and excluded.
    private func propertyRefsInConditionList(
        _ conditions: ConditionElementListSyntax,
        matching names: Set<String>,
        awaitRelatedNames: Set<String>
    ) -> Set<String> {
        var found: Set<String> = []

        for element in conditions {
            // Check whether this condition element is an optional binding
            let optBinding = element.children(viewMode: .sourceAccurate)
                .compactMap { $0.as(OptionalBindingConditionSyntax.self) }
                .first

            if let optBinding {
                // Extract the bound name (the `let x` part)
                let boundName = optBinding.pattern
                    .as(IdentifierPatternSyntax.self)?.identifier.text

                // If the bound name is used as an await operand, this is a resource guard —
                // the property is needed for the work, not just as a gate. Skip it.
                if let boundName, awaitRelatedNames.contains(boundName) {
                    continue
                }

                // Otherwise it's a potential scheduling sentinel — flag the property
                // referenced in the binding's initializer (the `= prop` part).
                if let initExpr = optBinding.initializer?.value {
                    found.formUnion(findPropertyReferences(in: Syntax(initExpr), matching: names))
                }
            } else {
                // Plain expression condition (e.g. `guard !isLoading`, `guard elapsed >= min`,
                // `guard connection != nil`).
                // Suppress any property that appears directly in await operands — those are
                // resource-presence checks (`x != nil`, `x.isReady`) rather than scheduling gates.
                let refs = findPropertyReferences(in: Syntax(element), matching: names)
                found.formUnion(refs.filter { !awaitRelatedNames.contains($0) })
                // NOTE: Residual false positive — when the property is consumed one call-stack
                // level below (e.g. `guard connection != nil` → `await self.send(…)` where
                // `send()` uses `connection` internally), the property name does not appear in
                // the local await operands and is still flagged. Suppressing it would require
                // data-flow / call-graph analysis beyond a syntax visitor.
            }
        }

        return found
    }

    private func findPropertyReferences(in syntax: Syntax, matching names: Set<String>) -> Set<String> {
        var found: Set<String> = []

        if let declRef = syntax.as(DeclReferenceExprSyntax.self) {
            if names.contains(declRef.baseName.text) {
                found.insert(declRef.baseName.text)
            }
        }

        if let memberAccess = syntax.as(MemberAccessExprSyntax.self),
           let base = memberAccess.base?.as(DeclReferenceExprSyntax.self),
           base.baseName.text == "self" {
            let name = memberAccess.declName.baseName.text
            if names.contains(name) {
                found.insert(name)
            }
        }

        for child in syntax.children(viewMode: .sourceAccurate) {
            found.formUnion(findPropertyReferences(in: child, matching: names))
        }

        return found
    }

    // MARK: - Assignment Detection

    private func collectAssignments(
        in syntax: Syntax,
        propertyNames: Set<String>,
        into results: inout [(name: String, position: AbsolutePosition)]
    ) {
        if syntax.is(FunctionDeclSyntax.self) || syntax.is(ClosureExprSyntax.self) {
            return
        }

        // Assignments in SwiftSyntax 602 are SequenceExprSyntax: [lhs, =, rhs]
        if let seqExpr = syntax.as(SequenceExprSyntax.self) {
            let elements = Array(seqExpr.elements)
            if elements.count >= 2, elements[1].is(AssignmentExprSyntax.self) {
                let lhs = elements[0]
                if let declRef = lhs.as(DeclReferenceExprSyntax.self),
                   propertyNames.contains(declRef.baseName.text) {
                    results.append((declRef.baseName.text, seqExpr.position))
                } else if let memberAccess = lhs.as(MemberAccessExprSyntax.self),
                          let base = memberAccess.base?.as(DeclReferenceExprSyntax.self),
                          base.baseName.text == "self" {
                    let name = memberAccess.declName.baseName.text
                    if propertyNames.contains(name) {
                        results.append((name, seqExpr.position))
                    }
                }
            }
        }

        for child in syntax.children(viewMode: .sourceAccurate) {
            collectAssignments(in: child, propertyNames: propertyNames, into: &results)
        }
    }

    // MARK: - Await Detection

    private func collectAwaitPositions(
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
