@testable import Core
import SwiftParser
@testable import SwiftProjectLintRules
import SwiftSyntax
import Testing

/// A key-path component, and a member of some other value, is not the actor's stored property.
///
/// Matched on name alone, both cut the same way twice. In a condition,
/// `jobs.contains(where: \.isLoading)` read as a check of the actor's own `isLoading` gate and was
/// reported. In an `await` operand, `send(jobs.map(\.isLoading))` read as the actor's `isLoading`
/// being the resource the await consumes, and a genuine unguarded `guard !isLoading` was dropped.
@Suite
struct ActorReentrancyKeyPathTests {

    private func issues(_ source: String) -> [LintIssue] {
        let visitor = ActorReentrancyVisitor(pattern: ActorReentrancy().pattern)
        visitor.walk(Parser.parse(source: source))
        return visitor.detectedIssues
    }

    // MARK: - Not the actor's property

    @Test
    func keyPathComponentInConditionIsNotTheGate() {
        let source = """
        actor Loader {
            var isLoading = false

            func refresh(_ jobs: [Job]) async {
                guard !jobs.contains(where: \\.isLoading) else { return }
                await fetch()
            }

            private func fetch() async {}
        }
        """
        #expect(issues(source).isEmpty)
    }

    @Test
    func anotherValuesMemberInConditionIsNotTheGate() {
        let source = """
        actor Loader {
            var isLoading = false

            func refresh(_ job: Job) async {
                guard !job.isLoading else { return }
                await fetch()
            }

            private func fetch() async {}
        }
        """
        #expect(issues(source).isEmpty)
    }

    @Test
    func conditionNamingNoStoredPropertyIsNotReported() {
        let source = """
        actor Loader {
            var isLoading = false

            func refresh(_ jobs: [Job]) async {
                guard !jobs.isEmpty else { return }
                await fetch()
            }

            private func fetch() async {}
        }
        """
        #expect(issues(source).isEmpty)
    }

    // MARK: - Still the actor's property

    @Test("the gate read bare or through self is still reported", arguments: [
        "guard !isLoading else { return }",
        "guard !self.isLoading else { return }"
    ])
    func genuineGateIsStillReported(condition: String) throws {
        let source = """
        actor Loader {
            var isLoading = false

            func refresh() async {
                \(condition)
                await fetch()
            }

            private func fetch() async {}
        }
        """
        let found = issues(source)
        #expect(found.count == 1)
        let issue = try #require(found.first)
        #expect(issue.message.contains("'isLoading'"))
    }

    // MARK: - Await operands

    @Test
    func keyPathComponentInAwaitOperandDoesNotHideTheGate() throws {
        let source = """
        actor Loader {
            var isLoading = false

            func report(_ jobs: [Job]) async {
                guard !isLoading else { return }
                await send(jobs.map(\\.isLoading))
            }

            private func send(_ flags: [Bool]) async {}
        }
        """
        let found = issues(source)
        #expect(found.count == 1)
        let issue = try #require(found.first)
        #expect(issue.message.contains("'isLoading'"))
    }

    @Test
    func closureInAwaitOperandDoesNotHideTheGate() {
        let source = """
        actor Loader {
            var isLoading = false

            func report(_ jobs: [Job]) async {
                guard !isLoading else { return }
                await send(jobs.map { j in j.flag })
            }

            private func send(_ flags: [Bool]) async {}
        }
        """
        #expect(issues(source).count == 1)
    }

    @Test
    func thePropertyItselfInAnAwaitOperandStillSuppresses() {
        // The resource-guard suppression is unchanged: here the await does consume `connection`.
        let source = """
        actor Server {
            var connection: Connection?

            func send(data: Data) async throws {
                guard connection != nil else { throw ServerError.notConnected }
                try await self.connection?.send(data)
            }
        }
        """
        #expect(issues(source).isEmpty)
    }
}
