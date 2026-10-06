import SwiftProjectLintModels
import SwiftProjectLintVisitors
import SwiftSyntax

/// A SwiftSyntax visitor that detects `catch` blocks that silently swallow errors.
///
/// A catch block is considered to handle the error when it does at least one of:
/// - **Rethrows**: contains a `throw` statement (not crossing closure/function boundaries)
/// - **Logs**: calls `print`, `debugPrint`, `NSLog`, `os_log`, or any method with a
///   logging-suggestive name (`log`, `error`, `warning`, `warn`, `debug`, `info`,
///   `critical`, `fault`, `verbose`, `trace`, `notice`)
/// - **Records a Swift Testing issue**: calls `Issue.record(...)` — Swift Testing's
///   diagnostic API. In test code, the canonical "unexpected-error-in-test-body"
///   pattern is `} catch { Issue.record("unexpected: \(error)") }` or
///   `} catch is ExpectedError { … }` followed by `Issue.record(...)` for the
///   unhandled-shape case. The presence of `Issue.record` in the catch body is
///   explicit handling — the test's framework consumes the recorded issue.
/// - **References the error variable**: the implicit `error` binding, or any name the
///   catch pattern binds (`catch let e as DecodingError`, `catch AppError.invalid(let
///   message)`), appears anywhere in the body — covers assignment to error state,
///   passing to callbacks, string interpolation, etc. It has to be the binding itself:
///   a member, implicit member or key-path component spelled the same
///   (`result.error`, `state = .error`, `\.error`) belongs to another value and does
///   not count.
/// - **Terminates explicitly**: calls `assertionFailure`, `fatalError`, or
///   `preconditionFailure`
///
/// Empty bodies, comment-only bodies, and bodies that update unrelated state
/// (e.g. `isLoading = false`) without touching the error are all flagged.
final class CatchWithoutHandlingVisitor: BasePatternVisitor {

    required init(pattern: SyntaxPattern, viewMode: SyntaxTreeViewMode = .sourceAccurate) {
        super.init(pattern: pattern, viewMode: viewMode)
    }

    override func visit(_ node: CatchClauseSyntax) -> SyntaxVisitorContinueKind {
        guard !isCatchHandled(node) else { return .visitChildren }

        addIssue(
            severity: .warning,
            message: "Catch block does not rethrow, log, or propagate the error",
            filePath: getFilePath(for: Syntax(node)),
            lineNumber: getLineNumber(for: Syntax(node)),
            suggestion: "Rethrow with 'throw error', log with 'print(error)' / 'logger.error(...)', "
                + "or assign to error state. Use 'swiftprojectlint:disable:next catch-without-handling' "
                + "if swallowing is intentional.",
            ruleName: .catchWithoutHandling
        )

        return .visitChildren
    }

    // MARK: - Handled Check

    func isCatchHandled(_ node: CatchClauseSyntax) -> Bool {
        let bodySyntax = Syntax(node.body)

        if containsThrow(in: bodySyntax) { return true }
        if containsLoggingCall(in: bodySyntax) { return true }
        if containsTestingDiagnosticCall(in: bodySyntax) { return true }
        if containsTerminatingCall(in: bodySyntax) { return true }

        let names = caughtNames(node)
        if names.contains(where: { containsReference(to: $0, in: bodySyntax) }) { return true }

        return false
    }

    // MARK: - Error Variable Names

    /// Every name the catch clause binds: `error` for an untyped `catch { }`, and otherwise each
    /// name its patterns bind — `e` in `catch let e as SomeError`, `message` in
    /// `catch AppError.invalid(let message)`. Using any of them uses what was caught. A typed arm
    /// that binds nothing (`catch is CancellationError`) falls back to `error`, which it does not
    /// bind, so only rethrowing, logging or terminating handles it.
    private func caughtNames(_ node: CatchClauseSyntax) -> Set<String> {
        var names: Set<String> = []
        for item in node.catchItems {
            guard let pattern = item.pattern else { continue }
            Self.collectBoundNames(in: Syntax(pattern), into: &names)
        }
        return names.isEmpty ? ["error"] : names
    }

    private static func collectBoundNames(in syntax: Syntax, into names: inout Set<String>) {
        if let identifier = syntax.as(IdentifierPatternSyntax.self) {
            names.insert(identifier.identifier.text)
            return
        }
        for child in syntax.children(viewMode: .sourceAccurate) {
            collectBoundNames(in: child, into: &names)
        }
    }

    // MARK: - Throw Detection (does not cross closure/function boundaries)

    func containsThrow(in syntax: Syntax) -> Bool {
        if syntax.is(ThrowStmtSyntax.self) { return true }
        if syntax.is(ClosureExprSyntax.self) { return false }
        if syntax.is(FunctionDeclSyntax.self) { return false }
        return syntax.children(viewMode: .sourceAccurate).contains { containsThrow(in: $0) }
    }

    // MARK: - Logging Call Detection

    private static let loggingFunctionNames: Set<String> = [
        "print", "debugPrint", "NSLog", "os_log", "os_signpost"
    ]

    func containsLoggingCall(in syntax: Syntax) -> Bool {
        if let call = syntax.as(FunctionCallExprSyntax.self) {
            // Direct functions: print(...), NSLog(...), etc.
            if let declRef = call.calledExpression.as(DeclReferenceExprSyntax.self),
               Self.loggingFunctionNames.contains(declRef.baseName.text) {
                return true
            }
            // Method calls: logger.error(...), os.log.debug(...), etc.
            if let member = call.calledExpression.as(MemberAccessExprSyntax.self),
               LoggingMethod.anyLogger.contains(member.declName.baseName.text) {
                return true
            }
        }
        return syntax.children(viewMode: .sourceAccurate).contains { containsLoggingCall(in: $0) }
    }

    // MARK: - Swift Testing Diagnostic Detection

    /// Detects `Issue.record(...)` — Swift Testing's API for recording an
    /// unexpected condition. The canonical test idiom for handling an
    /// unexpected error in a `do/catch` test body is:
    ///
    /// ```swift
    /// do {
    ///     try work()
    /// } catch is ExpectedError {
    ///     // expected — assertion below confirms the throw site
    /// } catch {
    ///     Issue.record("unexpected error type: \(error)")
    /// }
    /// ```
    ///
    /// `Issue.record` is the test framework's analogue of `print` / `logger.error`
    /// for test code — it routes the message to the test runner's diagnostic
    /// stream. Treating it as handling matches the existing logging-call
    /// exemption.
    ///
    /// Receiver-gated on the `Issue` type identifier to avoid collision with
    /// adopter-defined `record(...)` methods on unrelated types.
    func containsTestingDiagnosticCall(in syntax: Syntax) -> Bool {
        if let call = syntax.as(FunctionCallExprSyntax.self),
           let member = call.calledExpression.as(MemberAccessExprSyntax.self),
           member.declName.baseName.text == "record",
           let base = member.base?.as(DeclReferenceExprSyntax.self),
           base.baseName.text == "Issue" {
            return true
        }
        return syntax.children(viewMode: .sourceAccurate)
            .contains { containsTestingDiagnosticCall(in: $0) }
    }

    // MARK: - Terminating Call Detection

    private static let terminatingFunctionNames: Set<String> = [
        "assertionFailure", "fatalError", "preconditionFailure"
    ]

    func containsTerminatingCall(in syntax: Syntax) -> Bool {
        if let call = syntax.as(FunctionCallExprSyntax.self),
           let declRef = call.calledExpression.as(DeclReferenceExprSyntax.self),
           Self.terminatingFunctionNames.contains(declRef.baseName.text) {
            return true
        }
        return syntax.children(viewMode: .sourceAccurate).contains { containsTerminatingCall(in: $0) }
    }

    // MARK: - Error Variable Reference Detection (crosses closures, not nested functions)

    /// Whether `syntax` uses the caught error by name.
    ///
    /// Only a name looked up in scope is the caught error. `jobs.filter(\.error)` reads each
    /// job's `error`, `result.error` reads the result's and `self.error` is a stored property;
    /// none of them touches what was caught, and each used to count as handling it.
    func containsReference(to name: String, in syntax: Syntax) -> Bool {
        if let ref = syntax.as(DeclReferenceExprSyntax.self), ref.baseName.text == name,
           ref.isLexicalReference {
            return true
        }
        // Don't cross into nested function declarations (separate scope / separate error)
        if syntax.is(FunctionDeclSyntax.self) { return false }
        return syntax.children(viewMode: .sourceAccurate)
            .contains { containsReference(to: name, in: $0) }
    }
}
