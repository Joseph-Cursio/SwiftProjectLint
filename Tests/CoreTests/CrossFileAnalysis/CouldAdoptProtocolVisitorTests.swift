@testable import Core
import SwiftParser
@testable import SwiftProjectLintRules
import SwiftSyntax
import Testing

@Suite
struct CouldAdoptProtocolVisitorTests {

    private func analyze(files: [String: String]) -> [LintIssue] {
        var cache: [String: SourceFileSyntax] = [:]
        for (name, source) in files {
            cache[name] = Parser.parse(source: source)
        }
        let pattern = CouldAdoptProtocol().pattern
        let visitor = CouldAdoptProtocolVisitor(fileCache: cache)
        visitor.setPattern(pattern)

        for (name, ast) in cache {
            visitor.setFilePath(name)
            visitor.setSourceLocationConverter(SourceLocationConverter(fileName: name, tree: ast))
            visitor.walk(ast)
        }
        visitor.finalizeAnalysis()
        return visitor.detectedIssues.filter { $0.ruleName == .couldAdoptProtocol }
    }

    private let identityProtocol = """
        protocol Identity {
            var rawKey: String { get }
            var name: String { get }
            var category: String { get }
        }
        """

    /// A type with all the protocol's required properties that does not conform is flagged.
    @Test
    func structuralMatchWithoutConformanceFlags() throws {
        let issues = analyze(files: [
            "Models.swift": """
            \(identityProtocol)
            struct Widget {
                let rawKey: String
                let name: String
                let category: String
                let extra: Int
            }
            """
        ])

        #expect(issues.count == 1)
        let issue = try #require(issues.first)
        #expect(issue.message.contains("Widget"))
        #expect(issue.message.contains("Identity"))
    }

    /// An `@Observable` class that structurally matches a protocol is not nudged to adopt
    /// it — protocol-abstracting an observation model would sever SwiftUI tracking.
    @Test
    func observableMacroClassNotFlagged() {
        let issues = analyze(files: [
            "Models.swift": """
            \(identityProtocol)
            @Observable
            final class Widget {
                var rawKey: String = ""
                var name: String = ""
                var category: String = ""
                var extra: Int = 0
            }
            """
        ])

        #expect(issues.isEmpty)
    }

    /// Likewise for a legacy `ObservableObject` conformer (handled via skippedConformances).
    @Test
    func observableObjectConformerNotFlagged() {
        let issues = analyze(files: [
            "Models.swift": """
            \(identityProtocol)
            final class Widget: ObservableObject {
                var rawKey: String = ""
                var name: String = ""
                var category: String = ""
                var extra: Int = 0
            }
            """
        ])

        #expect(issues.isEmpty)
    }

    /// A type that already conforms is not flagged.
    @Test
    func alreadyConformingIsClean() {
        let issues = analyze(files: [
            "Models.swift": """
            \(identityProtocol)
            struct Widget: Identity {
                let rawKey: String
                let name: String
                let category: String
            }
            """
        ])

        #expect(issues.isEmpty)
    }

    /// Conformance declared with isolated-conformance syntax is recognized → not flagged.
    @Test
    func isolatedConformanceIsRecognized() {
        let issues = analyze(files: [
            "Models.swift": """
            \(identityProtocol)
            struct Widget: @MainActor Identity {
                let rawKey: String
                let name: String
                let category: String
            }
            """
        ])

        #expect(issues.isEmpty)
    }

    /// Missing one required property → not a match.
    @Test
    func partialMatchIsClean() {
        let issues = analyze(files: [
            "Models.swift": """
            \(identityProtocol)
            struct Widget {
                let rawKey: String
                let name: String
            }
            """
        ])

        #expect(issues.isEmpty)
    }

    /// Protocols with a non-property requirement are excluded (structural matching unreliable).
    @Test
    func protocolWithMethodRequirementIsIgnored() {
        let issues = analyze(files: [
            "Models.swift": """
            protocol Drawable {
                var rawKey: String { get }
                var name: String { get }
                var category: String { get }
                func draw()
            }
            struct Widget {
                let rawKey: String
                let name: String
                let category: String
            }
            """
        ])

        #expect(issues.isEmpty)
    }

    /// Protocols with fewer than three requirements are too generic to suggest adoption.
    @Test
    func tinyProtocolIsIgnored() {
        let issues = analyze(files: [
            "Models.swift": """
            protocol Named {
                var name: String { get }
                var id: String { get }
            }
            struct Widget {
                let name: String
                let id: String
            }
            """
        ])

        #expect(issues.isEmpty)
    }

    /// SwiftUI views that happen to match are skipped.
    @Test
    func viewConformersAreSkipped() {
        let issues = analyze(files: [
            "Views.swift": """
            \(identityProtocol)
            struct WidgetView: View {
                let rawKey: String
                let name: String
                let category: String
                var body: some View { EmptyView() }
            }
            """
        ])

        #expect(issues.isEmpty)
    }
}
