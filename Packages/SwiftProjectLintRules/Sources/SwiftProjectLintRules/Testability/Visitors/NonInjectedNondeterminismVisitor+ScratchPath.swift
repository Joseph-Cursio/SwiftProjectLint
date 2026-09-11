import Foundation
import SwiftProjectLintModels
import SwiftProjectLintVisitors
import SwiftSyntax

/// The scratch-path decline: a unique name for a file that does not outlive the call.
///
/// One gate with two arms, and the split between them is the interesting part. The first asks
/// *where* the path is — under the temporary directory — and the second asks what that location
/// was standing in for: *does a `defer` delete it?* The second arm exists because a tool that must
/// write into the directory it is working on cannot use the first and makes the same claim anyway.
///
/// These live in an extension because the visitor's own body is at its length limit, and because
/// they read as one group: every one of them answers *can this name escape the scope that made it?*
extension NonInjectedNondeterminismVisitor {

    /// True when `node` names a scratch path that does not outlive the call —
    /// `tmp.appendingPathComponent("import-\(UUID().uuidString)")`.
    ///
    /// Two arms say that, and `appendsToAPath` is common to both: the path roots at the temporary
    /// directory, or a `defer` in the same body deletes it. See `isRemovedInADefer` for why the
    /// second arm exists and what it is evidence of.
    ///
    /// The uniqueness *is* the point, and it is the one shape where a deterministic source would be
    /// actively wrong: two concurrent imports handed the same name would collide, and every one of
    /// these sites creates the directory, uses it, and deletes it on the way out. Nothing compares
    /// the name, stores it, or sends it anywhere, so there is no second value for it to disagree
    /// with — the test the fabrication branch applies, reached here from the other direction.
    ///
    /// Measured before the gate: 14 of 164 findings across the corpus, in eight repositories. That
    /// is the whole of what this buys, and it is worth having because a reader triaging the rest
    /// should not be shown fourteen findings the rule could have known were fine.
    ///
    /// **Only an identity source, and the first draft of this got that wrong.** It exempted
    /// anything nondeterministic in a temporary path name, which would have silenced
    /// `"run-\(Date())"` — and a clock read used to make a name unique is the shape that produced a
    /// real defect in SwiftMarkdownWiki's snapshot collision loop, which terminated *only* because
    /// the format carried milliseconds. A UUID is a name that cannot collide; a timestamp is a name
    /// that usually does not, which is a different claim.
    ///
    /// **`NSTemporaryDirectory()` counts, and the first version said it did not.** That claim came
    /// from a grep that searched a line at a time, and the corpus writes the call across two —
    /// `URL(fileURLWithPath: NSTemporaryDirectory())` on one line, the appended component on the
    /// next. One production site, and exempting `temporaryDirectory` but not the same intent
    /// spelled another way is arbitrary rather than conservative. A hard-coded `/tmp` still does
    /// not count: it does not appear, and that was checked with a pattern that can see it.
    func isScratchDirectoryName(_ node: Syntax, kind: NondeterminismSources.Kind) -> Bool {
        guard kind == .identity else { return false }
        var current = node
        while let parent = current.parent {
            if parent.is(ClosureExprSyntax.self) || parent.is(CodeBlockSyntax.self) { return false }
            // The *first* enclosing call decides. Walking past it would exempt a `UUID()` that
            // merely shares a statement with a path append, which is a different expression.
            if let call = parent.as(FunctionCallExprSyntax.self) {
                guard Self.appendsToAPath(call) else { return false }
                return Self.rootsAtTemporaryDirectory(call) || isRemovedInADefer(call)
            }
            current = parent
        }
        return false
    }

    /// Whether `call` is one of the path-appending methods, whatever it is rooted at.
    private static func appendsToAPath(_ call: FunctionCallExprSyntax) -> Bool {
        guard let callee = call.calledExpression.as(MemberAccessExprSyntax.self) else { return false }
        return pathAppendingMethods.contains(callee.declName.baseName.text)
    }

    private static func rootsAtTemporaryDirectory(_ call: FunctionCallExprSyntax) -> Bool {
        guard let base = call.calledExpression.as(MemberAccessExprSyntax.self)?.base else {
            return false
        }
        return rootsAtTemporaryDirectory(base)
    }

    /// Whether the path `call` builds is bound to a local that a `defer` in the same body deletes.
    ///
    /// **This is the evidence `temporaryDirectory` was standing in for.** The original gate required
    /// the path to root at the temporary directory, because a file there is ephemeral and its name is
    /// never compared or stored. That is a proxy, and it missed the case where a tool must write
    /// *into the directory it is working on*:
    ///
    /// ```swift
    /// let probeURL = targetDirectory.appendingPathComponent("_SwiftLintProbe_\(UUID().uuidString).swift")
    /// try probe.triggeringSource.write(to: probeURL, atomically: true, encoding: .utf8)
    /// defer { try? FileManager.default.removeItem(at: probeURL) }
    /// ```
    ///
    /// A probe that lints one rule against one snippet has to sit where `swiftlint` will find it, so
    /// the temporary directory is not available — and the uniqueness is load-bearing rather than
    /// incidental: a fixed name would let two concurrent verifications clobber each other's probe.
    /// The declaration says as much in its own words: *"briefly writes a uniquely-named `.swift` file
    /// into `targetDirectory`, removed immediately (even on error)."*
    ///
    /// A `defer` that deletes the file is a stronger statement than its location: it says the file
    /// does not outlive the scope, so nothing outside can have compared or stored its name.
    ///
    /// Still gated on `kind == .identity`, which is what keeps `"run-\(Date())"` reported — a
    /// timestamp name is one that *usually* does not collide, and the snapshot collision loop that
    /// terminated only because its format carried milliseconds is the defect that requirement exists
    /// for.
    private func isRemovedInADefer(_ call: FunctionCallExprSyntax) -> Bool {
        guard let clause = call.parent?.as(InitializerClauseSyntax.self),
              Syntax(clause.value).id == Syntax(call).id,
              let binding = clause.parent?.as(PatternBindingSyntax.self),
              let name = binding.pattern.as(IdentifierPatternSyntax.self)?.identifier.text,
              let body = Self.enclosingBlock(of: Syntax(binding)) else { return false }
        return Self.deletes(name, somewhereInADeferIn: body)
    }

    private static func enclosingBlock(of node: Syntax) -> Syntax? {
        var current = node.parent
        while let syntax = current {
            if syntax.is(CodeBlockSyntax.self) || syntax.is(ClosureExprSyntax.self) {
                return syntax
            }
            current = syntax.parent
        }
        return nil
    }

    /// Whether some `defer` inside `body` passes `name` to a removal call.
    private static func deletes(_ name: String, somewhereInADeferIn body: Syntax) -> Bool {
        var found = false
        forEachDefer(in: body) { deferred in
            if mentions(name, asArgumentOfARemovalIn: deferred) { found = true }
        }
        return found
    }

    private static func forEachDefer(in node: Syntax, _ visit: (Syntax) -> Void) {
        for child in node.children(viewMode: .sourceAccurate) {
            if let deferred = child.as(DeferStmtSyntax.self) { visit(Syntax(deferred.body)) }
            forEachDefer(in: child, visit)
        }
    }

    private static func mentions(
        _ name: String,
        asArgumentOfARemovalIn node: Syntax
    ) -> Bool {
        for child in node.children(viewMode: .sourceAccurate) {
            if let call = child.as(FunctionCallExprSyntax.self),
               let callee = call.calledExpression.as(MemberAccessExprSyntax.self),
               removalMethods.contains(callee.declName.baseName.text),
               call.arguments.contains(where: { argument in
                   argument.expression.tokens(viewMode: .sourceAccurate).contains { $0.text == name }
               }) {
                return true
            }
            if mentions(name, asArgumentOfARemovalIn: child) { return true }
        }
        return false
    }

    /// File-system removal methods. Narrow on purpose: a `defer` that logs, closes a handle or
    /// releases a lock says nothing about whether the file outlives the scope.
    private static let removalMethods: Set<String> = ["removeItem", "trashItem", "unlinkItem"]

    /// Walks a receiver chain looking for a `temporaryDirectory` member.
    ///
    /// Descends through further calls as well as member accesses, so a chain that appends twice —
    /// `tmp.appendingPathComponent("A").appendingPathComponent(id)` — still finds its root.
    private static func rootsAtTemporaryDirectory(_ expression: ExprSyntax) -> Bool {
        if callsTemporaryDirectoryFunction(Syntax(expression)) { return true }
        var current: ExprSyntax? = expression
        while let node = current {
            if let member = node.as(MemberAccessExprSyntax.self) {
                if member.declName.baseName.text == "temporaryDirectory" { return true }
                current = member.base
                continue
            }
            if let call = node.as(FunctionCallExprSyntax.self) {
                current = call.calledExpression
                continue
            }
            return false
        }
        return false
    }

    /// True when `syntax` contains a call to `NSTemporaryDirectory()`.
    ///
    /// A subtree scan rather than a chain walk, because the call sits inside a `URL` initialiser
    /// rather than at the head of a member chain: `URL(fileURLWithPath: NSTemporaryDirectory())`.
    /// Scanning the *receiver* of a path append is bounded — anything in it that names the
    /// temporary directory means the path being built is under it.
    private static func callsTemporaryDirectoryFunction(_ syntax: Syntax) -> Bool {
        if let call = syntax.as(FunctionCallExprSyntax.self),
           call.calledExpression.as(DeclReferenceExprSyntax.self)?
               .baseName.text == "NSTemporaryDirectory" {
            return true
        }
        return syntax.children(viewMode: .sourceAccurate).contains {
            callsTemporaryDirectoryFunction($0)
        }
    }

    /// The `URL` members that build a child path from a parent.
    private static let pathAppendingMethods: Set<String> = [
        "appendingPathComponent", "appending", "appendingPathExtension"
    ]
}
