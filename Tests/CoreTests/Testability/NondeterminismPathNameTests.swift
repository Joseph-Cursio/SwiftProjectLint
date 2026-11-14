import SwiftParser
import SwiftProjectLintModels
@testable import SwiftProjectLintRules
import SwiftProjectLintVisitors
import SwiftSyntax
import Testing

/// Composing a path name is a use of the read, whichever way the name is spelled.
///
/// `parent.appendingPathComponent(UUID().uuidString)` got the composition-root message, "handed
/// straight on", and `parent.appendingPathComponent("x-\(UUID().uuidString)")` got the ordinary
/// one. Both build a path from the read and a receiver this scope supplied, and the path is made
/// here, so both now get the ordinary message, which lists "a name" among the decisions worth a
/// seam. Every case is still reported exactly once: only the sentence moves.
@Suite("Non-Injected Nondeterminism — a composed path name")
struct NondeterminismPathNameTests {

    private func analyze(_ source: String) -> [LintIssue] {
        let visitor = NonInjectedNondeterminismVisitor(patternCategory: .testability)
        let syntax = Parser.parse(source: source)
        visitor.setSourceLocationConverter(SourceLocationConverter(fileName: "Logic.swift", tree: syntax))
        visitor.setFilePath("Logic.swift")
        visitor.walk(syntax)
        return visitor.detectedIssues.filter { $0.ruleName == .nonInjectedNondeterminism }
    }

    private func isCompositionRoot(_ source: String) -> Bool {
        analyze(source).first?.message.hasPrefix("Clock/RNG read at a composition root") ?? false
    }

    @Test("every spelling of a composed path name gets the ordinary message", arguments: [
        // MacCloud_server's blob path, the bare spelling.
        "func f(_ dir: URL) -> String { dir.appendingPathComponent(UUID().uuidString).path }",
        // SwiftLintRuleStudio's workspace folder, with a label that combines nothing.
        "func f(_ dir: URL) -> URL { dir.appendingPathComponent(UUID().uuidString, isDirectory: true) }",
        // SwiftAssist's shadow workspace, the interpolated spelling, which was already ordinary.
        "func f(_ dir: URL) -> URL { dir.appendingPathComponent(\"git-\\(UUID().uuidString)\") }",
        // The newer URL API and the extension append.
        "func f(_ dir: URL) -> URL { dir.appending(path: UUID().uuidString) }",
        "func f(_ dir: URL) -> URL { dir.appendingPathExtension(UUID().uuidString) }",
        // The bound spelling: the binding's one reference is the append.
        "func f(_ dir: URL) -> URL { let name = UUID().uuidString; return dir.appendingPathComponent(name) }",
    ])
    func composedPathNameIsOrdinary(source: String) {
        #expect(analyze(source).count == 1)
        #expect(isCompositionRoot(source) == false)
    }

    @Test("a name handed on whole is still a composition root")
    func nameHandedOnWholeIsStillACompositionRoot() {
        // Not composed here: the callee takes the identity as a parameter.
        #expect(isCompositionRoot("func f(_ c: C) { schedule(R(identifier: UUID().uuidString, content: c)) }"))
    }

    @Test("a scratch path is still declined before the arm is asked")
    func scratchPathIsStillDeclined() {
        #expect(analyze("""
        func f() -> URL {
            FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        }
        """).isEmpty)
    }
}
