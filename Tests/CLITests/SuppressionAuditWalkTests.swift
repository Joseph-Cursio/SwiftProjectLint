@testable import CLI
import Foundation
import SwiftProjectLintConfig
import Testing

/// The CLI half of the unrecognised-name diagnostic: walking the project and
/// naming files relative to its root.
///
/// `SuppressionAudit` itself is covered in `CoreTests`. What is only testable
/// here is that the walk honours the configuration's exclusions and reports a
/// path a reader can act on — an absolute path would be correct and useless in
/// a notice meant to be pasted into an editor.
@Suite
struct SuppressionAuditWalkTests {

    private func makeProject(_ files: [String: String]) throws -> URL {
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("spl-audit-\(UUID().uuidString)")
        for (relative, contents) in files {
            let path = root.appendingPathComponent(relative)
            try FileManager.default.createDirectory(
                at: path.deletingLastPathComponent(), withIntermediateDirectories: true
            )
            try contents.write(to: path, atomically: true, encoding: .utf8)
        }
        return root
    }

    @Test func reportsUnknownNamesWithRootRelativePaths() throws {
        let root = try makeProject([
            "Sources/Model.swift": "// swiftprojectlint:disable:next legacy-observable-object\nlet x = 1\n",
            "Sources/Fine.swift": "// swiftprojectlint:disable:next force-try\nlet y = 1\n"
        ])
        defer { try? FileManager.default.removeItem(at: root) }

        let found = SwiftProjectLintCLI.unrecognizedSuppressionNames(
            projectRoot: root.path, configuration: LintConfiguration()
        )
        #expect(found.count == 1)
        // Root-relative, not absolute: the notice is meant to be actionable.
        #expect(found.first?.filePath == "Sources/Model.swift")
        #expect(found.first?.suggestion == "legacy-observableobject")
    }

    @Test func skipsExcludedPaths() throws {
        let root = try makeProject([
            "Vendor/Model.swift": "// swiftprojectlint:disable:next totally-fictional-rule\nlet x = 1\n"
        ])
        defer { try? FileManager.default.removeItem(at: root) }

        let audited = SwiftProjectLintCLI.unrecognizedSuppressionNames(
            projectRoot: root.path, configuration: LintConfiguration()
        )
        #expect(audited.count == 1, "control: the file is found when nothing excludes it")

        let excluded = SwiftProjectLintCLI.unrecognizedSuppressionNames(
            projectRoot: root.path,
            configuration: LintConfiguration(excludedPaths: ["Vendor"])
        )
        #expect(excluded.isEmpty)
    }

    @Test func reportsNothingWhenEveryNameResolves() throws {
        let root = try makeProject([
            "Sources/A.swift": "// swiftprojectlint:disable:next force-try magic-number\nlet x = 1\n",
            "Sources/B.swift": "// swiftprojectlint:disable\nlet y = 1\n"
        ])
        defer { try? FileManager.default.removeItem(at: root) }

        #expect(SwiftProjectLintCLI.unrecognizedSuppressionNames(
            projectRoot: root.path, configuration: LintConfiguration()
        ).isEmpty)
    }
}
