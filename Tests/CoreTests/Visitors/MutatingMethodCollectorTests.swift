import SwiftParser
@testable import SwiftProjectLintVisitors
import SwiftSyntax
import Testing

@Suite
struct MutatingMethodCollectorTests {

    private func collect(from source: String) -> Set<String> {
        let collector = MutatingMethodCollector()
        collector.walk(Parser.parse(source: source))
        return collector.collectedTypes
    }

    @Test func collectsMutatingMethodsOnStructsEnumsAndExtensions() {
        let source = """
        struct RunGate {
            mutating func recordAttempt(at now: Date) {}
        }
        enum Phase {
            case idle, busy
            mutating func advance() { self = .busy }
        }
        extension RunGate {
            mutating func reset() {}
        }
        """
        #expect(collect(from: source) == ["recordAttempt", "advance", "reset"])
    }

    @Test func collectsMutatingProtocolRequirements() {
        #expect(collect(from: "protocol Gate { mutating func record() }") == ["record"])
    }

    @Test func ignoresNonMutatingMethods() {
        let source = """
        struct RunGate {
            func isDue() -> Bool { true }
            static func make() -> RunGate { RunGate() }
        }
        final class Box { func fill() {} }
        """
        #expect(collect(from: source).isEmpty)
    }
}
