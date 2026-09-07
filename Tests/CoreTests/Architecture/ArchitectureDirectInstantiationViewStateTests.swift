@testable import Core
import Foundation
import SwiftParser
@testable import SwiftProjectLintRules
import SwiftSyntax
import Testing

/// `Direct Instantiation`\'s `@Observable`-view-state gate. Separate from the main suite
/// because it needs a helper that primes `knownObservableTypes`, the project-wide prescan the
/// gate resolves against.
@Suite
struct ArchitectureDirectInstantiationViewStateTests {

    private func analyzeSource(
        _ source: String,
        observableTypes: Set<String>,
        filePath: String = "TestFile.swift"
    ) -> [LintIssue] {
        let visitor = DirectInstantiationVisitor(patternCategory: .architecture)
        visitor.knownObservableTypes = observableTypes
        let syntax = Parser.parse(source: source)
        let converter = SourceLocationConverter(fileName: filePath, tree: syntax)
        visitor.setSourceLocationConverter(converter)
        visitor.setFilePath(filePath)
        visitor.walk(syntax)
        return visitor.detectedIssues
    }

    @Test func testObservableModelOwnedByAViewIsNotReported() {
        // An `@Environment` value cannot be read from a property initializer, so a model that
        // needs one is built in `.task` and stored into an optional `@State`. That
        // construction *is* the injection — `appState` arrives from the environment — and the
        // rule's suggestion names the pre-Observation API for a problem Observation does not
        // have.
        let source = """
        struct BeadsView: View {
            @Environment(AppState.self) private var appState
            @State private var viewModel: BeadsViewModel?

            var body: some View {
                Text("beads").task {
                    if viewModel == nil {
                        viewModel = BeadsViewModel(appState: appState)
                    }
                }
            }
        }
        """
        let issues = analyzeSource(source, observableTypes: ["BeadsViewModel"])
            .filter { $0.ruleName == .directInstantiation }
        #expect(issues.isEmpty)
    }

    @Test func testNonObservableModelInAViewIsStillReported() throws {
        // The gate is `@Observable` ownership, not "anything built in a view". A plain service
        // reached for inside a view body is the case the rule exists for.
        let source = """
        struct BeadsView: View {
            @State private var viewModel: BeadsViewModel?

            var body: some View {
                Text("beads").task {
                    let runner = SwiftLintRunner()
                    _ = runner
                }
            }
        }
        """
        let issues = analyzeSource(source, observableTypes: ["BeadsViewModel"])
            .filter { $0.ruleName == .directInstantiation }
        let issue = try #require(issues.first)
        #expect(issue.message.contains("SwiftLintRunner"))
    }

    @Test func testObservableModelOutsideAViewIsStillReported() throws {
        // Scoped to `View`. The same `@Observable` type built by a service is an ordinary
        // dependency of that service.
        let source = """
        final class Coordinator {
            func start() {
                let model = BeadsViewModel(appState: appState)
                _ = model
            }
        }
        """
        let issues = analyzeSource(source, observableTypes: ["BeadsViewModel"])
            .filter { $0.ruleName == .directInstantiation }
        let issue = try #require(issues.first)
        #expect(issue.message.contains("BeadsViewModel"))
    }
}
