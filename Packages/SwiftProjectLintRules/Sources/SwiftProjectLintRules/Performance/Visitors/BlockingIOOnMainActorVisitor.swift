import Foundation
import SwiftProjectLintModels
import SwiftProjectLintVisitors
import SwiftSyntax

/// Detects synchronous file, network and wait calls in code that runs on the main actor.
///
/// Swift 6 rejects a data race at compile time, but a hang is not a type error: this compiles
/// cleanly in a `@MainActor` view model and freezes the UI until the disk answers.
///
/// ```swift
/// func loadReceipt() {
///     let data = try? Data(contentsOf: receiptURL)
/// }
/// ```
///
/// Cross-file, because isolation is declared in one place and used in another: an
/// `extension ContentView` in one file is `@MainActor` because `ContentView: View` is declared
/// in a different one. The walk records every type (`MainActorTypeTable`); `finalizeAnalysis`
/// then scans each file with the whole table in hand (`MainActorBlockingCallScanner`).
///
/// A file in a target built with default MainActor isolation (`defaultMainActorSourcePaths`)
/// starts on the main actor: there, code that says nothing runs on it.
final class BlockingIOOnMainActorVisitor: CrossFileVisitorBase, CrossFilePatternVisitorProtocol {

    private var table = MainActorTypeTable()
    private var walkedFiles: [(path: String, tree: SourceFileSyntax)] = []

    override func visit(_ node: SourceFileSyntax) -> SyntaxVisitorContinueKind {
        let path = currentFilePath
        guard Self.isExempt(path) == false else { return .skipChildren }
        walkedFiles.append((path, node))
        table.collect(from: node, defaultsToMainActor: isDefaultMainActorSource(path))
        return .skipChildren
    }

    func finalizeAnalysis() {
        for file in walkedFiles {
            let scanner = MainActorBlockingCallScanner(
                table: table, fileDefaultsToMainActor: isDefaultMainActorSource(file.path)
            )
            scanner.walk(file.tree)
            for finding in scanner.findings {
                report(finding, filePath: file.path)
            }
        }
    }

    private func report(_ finding: MainActorBlockingCallScanner.Finding, filePath: String) {
        addIssue(
            severity: .warning,
            message: "'\(finding.call.display)' \(finding.call.kind.phrase) — \(finding.reason)",
            filePath: filePath,
            lineNumber: getLineNumber(for: Syntax(finding.node)),
            suggestion: Self.suggestion(for: finding.call.kind),
            ruleName: .blockingIOOnMainActor
        )
    }

    static func suggestion(for kind: BlockingCall.Kind) -> String {
        switch kind {
        case .fileRead, .urlLoad, .fileWrite, .fileSystem, .network:
            "Move the work off the main actor and await it: into an actor, a @concurrent function "
                + "(Swift 6.2), or an async API such as URLSession.data(from:). Wrapping it in "
                + "Task { } does not help — the task inherits the main actor."

        case .wait:
            "Await the result instead of blocking for it: wrap the callback in "
                + "withCheckedContinuation, or call an async API."

        case .sleep:
            "Use try await Task.sleep(for:), which suspends instead of blocking the main thread."
        }
    }

    /// Test and fixture code, and package manifests, are not app code.
    private static func isExempt(_ path: String) -> Bool {
        let fileName = (path as NSString).lastPathComponent
        return isTestOrFixturePath(path) || fileName == "Package.swift" || fileName.hasPrefix("Package@swift")
    }
}
