import Foundation
import SwiftParser
import SwiftProjectLintModels
@testable import SwiftProjectLintRules
import SwiftProjectLintVisitors
import SwiftSyntax
import Testing

/// Creating a value because there is none is not fabricating one to fill a hole.
///
/// `ChatViewModel` writes `let sessionID = currentSessionID ?? UUID()` and then, at the end of the
/// same method, `currentSessionID = sessionID`. The corpus sweep reported that as a fabrication and
/// it was wrong: the invented id is not standing in for a real one that exists somewhere else, it
/// *becomes* the session's id, and nothing downstream can be misled about what it was.
///
/// Every true fabrication in the corpus shares the property this one lacks — the invented value has
/// a real counterpart it can disagree with. A write-back removes the counterpart.
///
/// **Suppressed here means reclassified, not silenced.** These fall through to the rule's ordinary
/// message, which is true of them: a test still cannot pin the id. That is why this gate moves the
/// corpus count by zero.
@Suite("A value written back is created, not fabricated")
struct NondeterminismLazyCreationTests {

    private func analyze(_ source: String) -> [LintIssue] {
        let visitor = NonInjectedNondeterminismVisitor(patternCategory: .testability)
        let syntax = Parser.parse(source: source)
        visitor.setSourceLocationConverter(
            SourceLocationConverter(fileName: "Logic.swift", tree: syntax)
        )
        visitor.setFilePath("Logic.swift")
        visitor.walk(syntax)
        return visitor.detectedIssues.filter { $0.ruleName == RuleIdentifier.nonInjectedNondeterminism }
    }

    /// The `ChatViewModel` shape, reduced. This is the finding the fifteenth sweep left standing.
    @Test("a binding written back later is not a fabrication")
    func bindingWrittenBackIsNotAFabrication() {
        let issues = analyze("""
        func save() {
            let sessionID = currentSessionID ?? UUID()
            store.save(sessionID)
            currentSessionID = sessionID
        }
        """)
        #expect(issues.count == 1)
        #expect(issues.first?.message.contains("Non-injected nondeterminism") == true)
    }

    /// The non-vacuity guard, and the reason the gate is the write-back rather than the binding:
    /// delete one line and the same code is a fabrication again.
    @Test("the same binding with no write-back is still a fabrication")
    func bindingWithoutWriteBackIsStillAFabrication() {
        let issues = analyze("""
        func save() {
            let sessionID = currentSessionID ?? UUID()
            store.save(sessionID)
        }
        """)
        #expect(issues.count == 1)
        #expect(issues.first?.message.contains("Fabricated fallback") == true)
    }

    @Test("the one-statement form is recognised too")
    func selfAssignmentIsNotAFabrication() {
        let issues = analyze("""
        func ensure() {
            currentSessionID = currentSessionID ?? UUID()
        }
        """)
        #expect(issues.count == 1)
        #expect(issues.first?.message.contains("Non-injected nondeterminism") == true)
    }

    @Test("self. and the bare name are the same storage")
    func selfPrefixDoesNotDefeatTheGate() {
        let issues = analyze("""
        func save() {
            let sessionID = self.currentSessionID ?? UUID()
            currentSessionID = sessionID
        }
        """)
        #expect(issues.first?.message.contains("Non-injected nondeterminism") == true)
    }

    @Test("a write-back nested in a branch still counts")
    func writeBackInsideABranchCounts() {
        let issues = analyze("""
        func save() {
            let sessionID = currentSessionID ?? UUID()
            if shouldPersist {
                currentSessionID = sessionID
            }
        }
        """)
        #expect(issues.first?.message.contains("Non-injected nondeterminism") == true)
    }

    /// The gate must not reach the DTO defects it sits next to. `self.id = model.id ?? UUID()` has
    /// an assignment in the very same sequence, and its left-hand side is a *different* storage
    /// from the operand the `??` falls back from — which is exactly why those clients receive a
    /// UUID matching no row.
    @Test("assigning into somewhere else is still a fabrication")
    func assigningIntoDifferentStorageIsStillAFabrication() {
        let issues = analyze("""
        struct Response: Identifiable {
            let id: UUID
            init(model: Model) {
                self.id = model.id ?? UUID()
            }
        }
        """)
        #expect(issues.count == 1)
        #expect(issues.first?.message.contains("Fabricated fallback") == true)
    }

    /// A write-back needs somewhere to write. `attributes.date() ?? Date()` falls back from a call,
    /// so the gate stays shut rather than guessing what storage was meant.
    @Test("a fallback from a call cannot be lazy creation")
    func fallbackFromACallIsStillAFabrication() {
        let issues = analyze("""
        func stamp(_ attributes: Attributes) -> Date {
            let modified = attributes.date() ?? Date()
            return modified
        }
        """)
        #expect(issues.count == 1)
        #expect(issues.first?.message.contains("Fabricated fallback") == true)
    }

    /// Writing back a *different* value is not a write-back. Guards against matching on the target
    /// alone and exempting anything that happens to assign to it.
    @Test("assigning something else back is still a fabrication")
    func assigningADifferentValueIsStillAFabrication() {
        let issues = analyze("""
        func save() {
            let sessionID = currentSessionID ?? UUID()
            currentSessionID = fallbackSessionID
            store.save(sessionID)
        }
        """)
        #expect(issues.count == 1)
        #expect(issues.first?.message.contains("Fabricated fallback") == true)
    }
}
