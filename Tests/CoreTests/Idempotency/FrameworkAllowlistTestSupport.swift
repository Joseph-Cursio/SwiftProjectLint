import SwiftParser
import SwiftSyntax
import Testing

/// The first call in a source snippet, outermost first.
private final class FirstCallFinder: SyntaxVisitor {
    var call: FunctionCallExprSyntax?

    init() { super.init(viewMode: .sourceAccurate) }
    override func visit(_ node: FunctionCallExprSyntax) -> SyntaxVisitorContinueKind {
        if call == nil { call = node }
        return .skipChildren
    }
}

/// The first member-access call to `method` in a source snippet.
private final class MemberCallFinder: SyntaxVisitor {
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

/// Shared helpers for the FrameworkAllowlist*, HeuristicInference* and receiver-type suites,
/// which conform to reach `firstCall(in:)` and `memberCall(method:in:)` without a type prefix.
/// Suites with their own helper of the same name keep it: a member declared in the type
/// shadows this extension's.
protocol FrameworkAllowlistTestSupport {}

extension FrameworkAllowlistTestSupport {
    func firstCall(in source: String) throws -> FunctionCallExprSyntax {
        let finder = FirstCallFinder()
        finder.walk(Parser.parse(source: source))
        return try #require(finder.call)
    }

    /// Locates a specific member-access call by method name in a source
    /// snippet. Needed to pick the terminal `.all()` / `.first()` etc.
    /// out of a chained expression where `firstCall` would return the
    /// outer-most call.
    func memberCall(method: String, in source: String) throws -> FunctionCallExprSyntax {
        let finder = MemberCallFinder(method: method)
        finder.walk(Parser.parse(source: source))
        return try #require(finder.call, "expected a call to .\(method)")
    }
}
