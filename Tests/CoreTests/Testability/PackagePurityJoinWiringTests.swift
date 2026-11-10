@testable import Core
import Foundation
import SwiftParser
import SwiftProjectLintModels
@testable import SwiftProjectLintRules
@testable import SwiftProjectLintVisitors
import SwiftSyntax
import Testing

/// **End-to-end: the join must actually be wired, not merely correct.**
///
/// The join was right and inert for a full build cycle. It sat behind
/// `knownImpurePackageFunctions`, which the pre-scan populated and *one* of the two
/// per-file detector construction sites forwarded — so `ProjectLinter` produced
/// byte-identical output with the gate present and absent. Measured on a real
/// corpus at the time: **0 suppressed**, where the unit tests above were all green.
///
/// Unit tests cannot catch that. They set `knownImpurePackageFunctions` themselves,
/// which is exactly the wiring in question. Only a run through `ProjectLinter` can
/// tell a correct gate from a gate nothing calls.
@Suite("The callee join is wired end to end, not just correct in isolation")
struct PackagePurityJoinWiringTests {

    /// A caller of an I/O helper, plus a sentinel candidate, in separate files so the
    /// join has to cross a file boundary the way it does in production.
    private func makeProject() -> String {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("PurityJoinWiring-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)

        let helper = """
        import Foundation

        func writeAudit(_ text: String) -> Int {
            FileHandle.standardError.write(Data(text.utf8))
            return text.count
        }
        """
        let caller = """
        func auditedLength(_ text: String) -> Int {
            writeAudit(text)
        }

        func sentinelJoin(_ first: Int, _ second: Int) -> Int {
            first + second
        }
        """
        try? helper.write(
            to: root.appendingPathComponent("Helper.swift"), atomically: true, encoding: .utf8
        )
        try? caller.write(
            to: root.appendingPathComponent("Caller.swift"), atomically: true, encoding: .utf8
        )
        return root.path
    }

    @Test("ProjectLinter does not offer a candidate whose callee it refutes")
    func joinIsWiredThroughProjectLinter() async {
        let projectPath = makeProject()
        defer { try? FileManager.default.removeItem(atPath: projectPath) }

        let system = PatternRegistryFactory.createConfiguredSystem()
        let issues = await ProjectLinter().analyzeProject(
            at: projectPath, detector: system.detector
        )
        let candidates = Set(
            issues
                .filter { $0.ruleName == .pureFunctionCandidate }
                .compactMap(\.symbol)
        )

        #expect(
            candidates.contains("sentinelJoin"),
            "the rule produced nothing, so the absence below proves nothing"
        )
        #expect(
            candidates.contains("auditedLength") == false,
            "`auditedLength` calls `writeAudit`, which writes to stderr — join not wired"
        )
    }
}
