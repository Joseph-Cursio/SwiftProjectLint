import Testing
@testable import SwiftProjectLintVisitors
import SwiftSyntax
import SwiftParser

/// Reproduces the exact structure of the R5 Run D noise site in
/// pointfreeco's `removeBetaAccess`. The receiver `users` is declared
/// inside a trailing closure as `var users = [owner]`, then mutated via
/// `users.append(contentsOf:)` inside a nested if-let. If the resolver
/// handles this shape correctly, `CallSiteEffectInferrer.infer(call:)`
/// must return nil at the `append` site.
@Suite
struct ReceiverTypeR5RepoFixtureTests {

    private func findAppendCall(_ source: String) throws -> FunctionCallExprSyntax {
        final class Finder: SyntaxVisitor {
            var call: FunctionCallExprSyntax?
            init() { super.init(viewMode: .sourceAccurate) }
            override func visit(_ node: FunctionCallExprSyntax) -> SyntaxVisitorContinueKind {
                if call == nil,
                   let member = node.calledExpression.as(MemberAccessExprSyntax.self),
                   member.declName.baseName.text == "append" {
                    call = node
                }
                return .visitChildren
            }
        }
        let finder = Finder()
        finder.walk(Parser.parse(source: source))
        return try #require(finder.call)
    }

    @Test
    func r5RemoveBetaAccessShape_resolvesToArray() throws {
        let source = """
        func removeBetaAccess(for subscription: Subscription) async {
          await withErrorReporting("Remove beta access") {
            let owner = try await database.fetchUser(id: subscription.userId)
            var users = [owner]
            if let teammates = try? await database.fetchSubscriptionTeammatesByOwnerId(owner.id) {
              users.append(contentsOf: teammates)
            }
          }
        }
        """
        let call = try findAppendCall(source)
        #expect(ReceiverShapes.resolve(receiverOf: call) == .stdlibCollection("Array"))
    }

    @Test
    func r5RemoveBetaAccessShape_inferenceReturnsNil() throws {
        let source = """
        func removeBetaAccess(for subscription: Subscription) async {
          await withErrorReporting("Remove beta access") {
            let owner = try await database.fetchUser(id: subscription.userId)
            var users = [owner]
            if let teammates = try? await database.fetchSubscriptionTeammatesByOwnerId(owner.id) {
              users.append(contentsOf: teammates)
            }
          }
        }
        """
        let call = try findAppendCall(source)
        #expect(CallSiteEffectInferrer.infer(call: call) == nil)
    }
}
