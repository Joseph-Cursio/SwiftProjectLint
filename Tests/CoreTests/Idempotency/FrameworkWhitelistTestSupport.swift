import Testing
@testable import Core
@testable import SwiftProjectLintRules
@testable import SwiftProjectLintVisitors
import SwiftSyntax
import SwiftParser

// Shared helpers for the FrameworkWhitelist* test suites. Promoted to
// module-scope so every split file can reach them without the verbose
// `Type.` prefix that would push call sites past the line_length limit.
// Other idempotency suites keep their own `private func firstCall/memberCall`
// helpers — member lookup shadows these at usage sites inside those types,
// so there is no ambiguity.

func firstCall(in source: String) throws -> FunctionCallExprSyntax {
    final class Finder: SyntaxVisitor {
        var call: FunctionCallExprSyntax?
        init() { super.init(viewMode: .sourceAccurate) }
        override func visit(_ node: FunctionCallExprSyntax) -> SyntaxVisitorContinueKind {
            if call == nil { call = node }
            return .skipChildren
        }
    }
    let finder = Finder()
    finder.walk(Parser.parse(source: source))
    return try #require(finder.call)
}

/// Locates a specific member-access call by method name in a source
/// snippet. Needed to pick the terminal `.all()` / `.first()` etc.
/// out of a chained expression where `firstCall` would return the
/// outer-most call.
func memberCall(method: String, in source: String) throws -> FunctionCallExprSyntax {
    final class Finder: SyntaxVisitor {
        let method: String
        var call: FunctionCallExprSyntax?
        init(method: String) {
            self.method = method
            super.init(viewMode: .sourceAccurate)
        }
        override func visit(_ node: FunctionCallExprSyntax) -> SyntaxVisitorContinueKind {
            if call == nil,
               let member = node.calledExpression.as(MemberAccessExprSyntax.self),
               member.declName.baseName.text == method {
                call = node
            }
            return .visitChildren
        }
    }
    let finder = Finder(method: method)
    finder.walk(Parser.parse(source: source))
    return try #require(finder.call, "expected a call to .\(method)")
}
