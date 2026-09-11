@testable import Core
import Foundation
import SwiftParser
@testable import SwiftProjectLintRules
import SwiftSyntax
import Testing

/// Which of the two laws the path/string arm states, and on what evidence.
///
/// Split from `ExtractableTotalKernelVisitorTests` only to keep either half under
/// `type_body_length`; the fixtures belong to the same suite of silences and fires.
///
/// The arm's gate is a **string** derivation that governs a decision, and its advice used to talk
/// about a path under a root regardless. Measured over 26 repositories, two of its six findings
/// derive no path at all, and one of the eight it carried in an earlier run pointed a reader at
/// `url` while the live bug two lines below was a byte budget that let 410 KB through a 16 KB cap.
@Suite("Extractable Total Kernel — the law the string shape is told it owes")
struct ExtractableTotalKernelStringLawTests {

    private func analyze(_ source: String, filePath: String = "Service.swift") -> [LintIssue] {
        let visitor = ExtractableTotalKernelVisitor(patternCategory: .testability)
        let syntax = Parser.parse(source: source)
        visitor.setSourceLocationConverter(
            SourceLocationConverter(fileName: filePath, tree: syntax)
        )
        visitor.setFilePath(filePath)
        visitor.walk(syntax)
        return visitor.detectedIssues.filter { $0.ruleName == .extractableTotalKernel }
    }

    //
    // The gate is a *string* derivation that governs a decision; the advice used to be about a
    // path under a root regardless. Measured over 26 repositories, two of the six findings on this
    // arm derive no path at all. Both fixtures below are those two, reduced.

    @Test("a lossy canonicalisation used as a dedup key is not told to round-trip from a root")
    func canonicalisationGetsTheStringLaw() throws {
        // `AppleDocsIngester.crawlFramework`. `lowercased()` is idempotent and does NOT
        // round-trip, so half the path advice is false here and the other half mentions a root
        // that does not exist.
        let issue = try #require(analyze("""
        func crawl(_ framework: String) async throws {
            var visited: Set<String> = []
            var queue: [(path: String, depth: Int)] = [("/documentation/" + framework.lowercased(), 0)]
            while !queue.isEmpty {
                let (path, depth) = queue.removeFirst()
                let normalizedPath = path.lowercased()
                guard !visited.contains(normalizedPath) else { continue }
                visited.insert(normalizedPath)
            }
        }
        """).first)

        #expect(issue.message.contains("TOTAL over the strings it names"))
        #expect(issue.message.contains("IDEMPOTENT"))
        #expect(issue.message.contains("rebuilding the whole from the root") == false)
    }

    @Test("a head/tail split is not told to round-trip from a root")
    func headTailSplitGetsTheStringLaw() throws {
        // `SkillConflictDetector.tier3MergeProposal`. This one DOES owe a recombination law — the
        // name and the body rejoin to the output — which is why the string advice states that as a
        // conditional rather than dropping round-trip altogether.
        //
        // The `await` is load-bearing, not decoration. This rule is *the kernel trapped in an
        // impure method*; take the I/O away and the whole function is pure, which is
        // `pureFunctionCandidate`'s finding instead and this rule correctly says nothing.
        let issue = try #require(analyze("""
        func propose(_ rationale: String) async throws -> MergeProposal {
            let output = try await collectResponse(task: .merge, prompt: rationale)
            guard !output.isEmpty else { throw SkillError.empty }
            let lines = output.split(separator: "\n", maxSplits: 1)
            let mergedName = String(lines.first ?? "merged-skill")
            let mergedPrompt = lines.count > 1 ? String(lines[1]) : output
            return MergeProposal(name: mergedName, draft: mergedPrompt)
        }
        """).first)

        #expect(issue.message.contains("RECOMBINE"))
        #expect(issue.message.contains("no separator"))
        #expect(issue.message.contains("rebuilding the whole from the root") == false)
    }

    @Test("a method deriving both a path and a plain string says which the root law is over")
    func mixedShapeNamesThePathBindings() throws {
        // `EditTools.execute`. Two unrelated derivations in one method, one finding. Without the
        // caveat a reader is told to check round-trip from a root about a line count.
        let issue = try #require(analyze("""
        func execute(_ url: URL, content: String) throws {
            let parent = url.deletingLastPathComponent()
            try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
            try content.write(to: url, atomically: true, encoding: .utf8)
            let lineCount = content.components(separatedBy: "\n").count
            if lineCount > 0 { log(lineCount) }
        }
        """).first)

        #expect(issue.message.contains("rebuilding the whole from the root"))
        #expect(issue.message.contains("That law is over `parent`"))
        #expect(issue.message.contains("`lineCount`"))
    }

    @Test("path evidence anywhere in the body keeps the root law")
    func pathEvidenceIsBodyWideNotBindingScoped() throws {
        // The scope choice, pinned. `scanSync`'s two bindings are built entirely from generic
        // string operations — `hasSuffix`, `hasPrefix`, `dropFirst` — and what makes it a path
        // derivation is the `lastPathComponent` on the following line. A binding-scoped check
        // gets the most canonical case in the corpus wrong, which is how the scope was chosen.
        let issue = try #require(analyze("""
        func scanSync(rootPath: String) -> DirectoryNode {
            let enumerator = FileManager.default.enumerator(atPath: rootPath)
            let prefix = rootPath.hasSuffix("/") ? rootPath : rootPath + "/"
            while let item = enumerator?.nextObject() as? String {
                let relativePath = item.hasPrefix(prefix)
                    ? String(item.dropFirst(prefix.count))
                    : item
                let dirName = (relativePath as NSString).lastPathComponent
                if skipped.contains(dirName) { continue }
            }
            return root
        }
        """).first)

        #expect(issue.message.contains("rebuilding the whole from the root"))
        // No named subset to report: the evidence is not attached to a binding.
        #expect(issue.message.contains("That law is over") == false)
    }

    @Test("path evidence inside a closure counts, though the kernel walk stops there")
    func pathEvidenceDescendsIntoClosures() throws {
        // `Sitrep.detectFiles`. The whole path derivation sits inside the `contains` closure —
        // the exclusion-by-prefix shape, where `["Sources/App"]` also excludes `Sources/AppExtension`.
        let issue = try #require(analyze("""
        func detectFiles(excludedPath: [String]) -> [URL] {
            let enumerator = FileManager.default.enumerator(at: rootURL)
            while let objectURL = enumerator?.nextObject() as? URL {
                let isExcluded = excludedPath.contains {
                    objectURL.deletingLastPathComponent().relativePath.hasPrefix($0)
                }
                let other = excludedPath.contains {
                    objectURL.deletingLastPathComponent().relativePath.hasPrefix($0)
                }
                guard isExcluded == false, other == false else { continue }
            }
            return []
        }
        """).first)

        #expect(issue.message.contains("rebuilding the whole from the root"))
    }
}
