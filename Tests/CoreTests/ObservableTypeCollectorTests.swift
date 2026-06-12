@testable import Core
import SwiftParser
@testable import SwiftProjectLintRules
import SwiftProjectLintVisitors
import SwiftSyntax
import Testing

@Suite
struct ObservableTypeCollectorTests {

    private func collect(from source: String) -> Set<String> {
        let syntax = Parser.parse(source: source)
        let collector = ObservableTypeCollector()
        collector.walk(syntax)
        return collector.collectedTypes
    }

    @Test func collectsObservableMacroClass() {
        let source = """
        @Observable
        final class SessionStore {
            var token = ""
        }
        """
        #expect(collect(from: source) == ["SessionStore"])
    }

    @Test func collectsObservableMacroWithOtherAttributes() {
        let source = """
        @MainActor
        @Observable
        final class AppModel {
            var count = 0
        }
        """
        #expect(collect(from: source) == ["AppModel"])
    }

    @Test func collectsObservableObjectConformer() {
        let source = """
        final class LegacyStore: ObservableObject {
            @Published var value = 0
        }
        """
        #expect(collect(from: source) == ["LegacyStore"])
    }

    @Test func ignoresPlainClass() {
        let source = """
        final class PlainService {
            func run() { }
        }
        """
        #expect(collect(from: source).isEmpty)
    }

    @Test func ignoresUnrelatedAttribute() {
        let source = """
        @MainActor
        final class Coordinator {
            func start() { }
        }
        """
        #expect(collect(from: source).isEmpty)
    }
}
