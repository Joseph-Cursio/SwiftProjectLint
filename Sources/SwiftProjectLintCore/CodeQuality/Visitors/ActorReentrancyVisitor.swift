import SwiftSyntax

/// A SwiftSyntax visitor that detects actor reentrancy risks.
///
/// Flags async functions inside actors where a stored property is checked in a guard/if
/// condition but not updated before an `await`, allowing concurrent callers to pass
/// the same guard and trigger duplicate work.
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

        // 1. Collect property references from guard/if conditions
        var propertyChecks: [(name: String, position: AbsolutePosition)] = []
        collectPropertyChecksFromConditions(
            in: bodySyntax, storedVarNames: storedVarNames, into: &propertyChecks
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

    // MARK: - Condition Property Checks

    private func collectPropertyChecksFromConditions(
        in syntax: Syntax,
        storedVarNames: Set<String>,
        into results: inout [(name: String, position: AbsolutePosition)]
    ) {
        // Don't descend into nested functions or closures
        if syntax.is(FunctionDeclSyntax.self) || syntax.is(ClosureExprSyntax.self) {
            return
        }

        if let guardStmt = syntax.as(GuardStmtSyntax.self) {
            let refs = findPropertyReferences(
                in: Syntax(guardStmt.conditions), matching: storedVarNames
            )
            for ref in refs {
                results.append((ref, guardStmt.position))
            }
        } else if let ifExpr = syntax.as(IfExprSyntax.self) {
            let refs = findPropertyReferences(
                in: Syntax(ifExpr.conditions), matching: storedVarNames
            )
            for ref in refs {
                results.append((ref, ifExpr.position))
            }
        }

        for child in syntax.children(viewMode: .sourceAccurate) {
            collectPropertyChecksFromConditions(in: child, storedVarNames: storedVarNames, into: &results)
        }
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
