@testable import Core
import Foundation
import Testing

extension ExtractableTotalKernelVisitorTests {
    // MARK: - The advice names the resume-index shape when the tiler has one (B18)

    /// **A tiler whose loop resumes from an externally-seeded index must warn the reader off lifting
    /// that index as its own scalar.** Naming the tiler shape (B16) moved the resume-counter bug from
    /// 1/3 to 2/3 in a cold-reader walk; the miss that held it there was a reader who extracted the
    /// resume point — `var index = current.queuedChunks` — as a separate `func resumeIndex(...) ->
    /// Int`, a shape carrying no tiling law, and so walked past the bug at the right line. The
    /// suggestion now says the resume point is the tiler's clamped `startIndex`.
    @Test("a tiler with a server-seeded resume index is told to fold it in as a clamped startIndex")
    func resumableTilerSuggestsFoldingTheIndexIn() throws {
        let issue = try #require(analyze("""
        func uploadRemainingChunks(of data: Data, chunkSize: Int) async throws {
            let totalChunks = (data.count + chunkSize - 1) / chunkSize
            var index = current.queuedChunks
            while index < totalChunks {
                let chunk = Data(data.dropFirst(index * chunkSize).prefix(chunkSize))
                _ = try await uploadChunk(chunk)
                index += 1
            }
        }
        """).first)

        let suggestion = try #require(issue.suggestion)
        // Still the tiler advice (B16 unchanged) …
        #expect(suggestion.contains("maps a part INDEX to its slice"))
        // … plus the resume-index clause (B18): it is the tiler's clamped startIndex, not a scalar.
        #expect(suggestion.contains("startIndex"))
        #expect(suggestion.contains("clamped to `0...count`"))
        #expect(suggestion.contains("resumeIndex"))
    }

    /// A tiler whose loop starts from a **literal `0`** has no resume concept, so the B18 clause must
    /// stay silent — naming a clamp there would be cargo-culting a bug the code cannot have.
    @Test("a tiler that starts from a literal 0 keeps the plain tiler advice, no resume clause")
    func nonResumableTilerOmitsTheResumeClause() throws {
        // Identical to the resumable case above except the seed — `var index = 0`, not a server
        // counter — so this isolates exactly the B18 signal.
        let issue = try #require(analyze("""
        func splitEvenly(_ data: Data, chunkSize: Int) async throws {
            let totalChunks = (data.count + chunkSize - 1) / chunkSize
            var index = 0
            while index < totalChunks {
                let chunk = Data(data.dropFirst(index * chunkSize).prefix(chunkSize))
                _ = try await upload(chunk)
                index += 1
            }
        }
        """).first)

        let suggestion = try #require(issue.suggestion)
        #expect(suggestion.contains("maps a part INDEX to its slice"))
        #expect(suggestion.contains("startIndex") == false)
        #expect(suggestion.contains("resumeIndex") == false)
    }

    // MARK: - The path/string shape
    //
    // The second kernel shape, added after the rule scored ZERO on a 60k-line linter. The
    // arithmetic gate wants an operator reaching a bound; a path kernel derives one string from
    // another and then decides with it, so every gate walked past it. Both fixtures below are real
    // functions from this repository and from SwiftInferProperties, not invented shapes.

    @Test("a path relativised against a normalised root is a candidate")
    func pathDerivationIsCandidate() throws {
        // `DirectoryScanner.scanSync`. Two chained derivations — normalise the root, then make the
        // item relative to it — governing a slice. `dropFirst(prefix.count)` is a slice with no
        // arithmetic operator anywhere in it, which is exactly why the arithmetic gate misses it.
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

        #expect(issue.message.contains("`prefix`"))
        #expect(issue.message.contains("ROUND-TRIP"))
        #expect(try #require(issue.suggestion).contains("relativePath(of item: String"))
    }

    @Test("a walk-up loop whose parent comparison governs the derivation is a candidate")
    func walkUpIsCandidate() throws {
        // SwiftInferProperties' `findPackageRoot`, inlined in eight files. The law is that the walk
        // TERMINATES — repeatedly taking the parent reaches a fixed point — and it is unreachable
        // from a test because the derivation is welded to a hardcoded `FileManager.default`.
        let issue = try #require(analyze("""
        func findPackageRoot(startingFrom directory: URL) -> URL? {
            var current = directory.standardizedFileURL
            while true {
                let manifest = current.appendingPathComponent("Package.swift")
                if FileManager.default.fileExists(atPath: manifest.path) {
                    return current
                }
                let parent = current.deletingLastPathComponent().standardizedFileURL
                if parent == current {
                    return nil
                }
                current = parent
            }
        }
        """).first)

        #expect(issue.message.contains("`manifest`"))
        #expect(issue.message.contains("IDEMPOTENT"))
    }

    // MARK: - Silences that keep the path shape honest

    @Test("one derived string governing nothing is not a kernel")
    func singleDerivationIsNotReported() {
        // The clause the third gate was protecting. A display string is derived and returned; no
        // slice, no membership test, no comparison naming it. Admitting this would fire on every
        // function in every codebase that builds a label.
        #expect(analyze("""
        func writeReport(to path: String, name: String) throws {
            let title = name.trimmingCharacters(in: .whitespaces).capitalized
            try title.write(toFile: path, atomically: true, encoding: .utf8)
        }
        """).isEmpty)
    }

    @Test("a derivation through an unknown helper is not vouched for")
    func opaqueHelperIsNotReported() {
        // Same conservatism as the arithmetic shape: the rule will not vouch for work it cannot
        // see. `sanitize` might read the disk for all this visitor knows.
        #expect(analyze("""
        func store(root: String, item: String) throws {
            let prefix = sanitize(root)
            let relative = String(item.dropFirst(prefix.count))
            if skipped.contains(relative) { return }
            try FileManager.default.removeItem(atPath: relative)
        }
        """).isEmpty)
    }

    @Test("a constant slice is not a derived one")
    func constantSliceIsNotReported() {
        // `dropFirst(1)` reads no count and derives nothing — the count reference is what makes a
        // slice evidence of a kernel.
        #expect(analyze("""
        func trim(root: String, item: String) throws {
            let head = item.lowercased()
            let tail = String(head.dropFirst(1))
            try tail.write(toFile: root, atomically: true, encoding: .utf8)
        }
        """).isEmpty)
    }

    @Test("string concatenation in an unrelated comparison does not vouch for a derivation")
    func unrelatedConcatenationDoesNotGovern() {
        // The bug in the first cut of this shape. `governingComparisonReferencing` returns true for
        // ANY comparison containing an arithmetic operator, and `+` on strings is concatenation —
        // so `label + suffix == other` vouched for derivations it had nothing to do with. The path
        // shape requires the comparison to actually NAME the binding.
        #expect(analyze("""
        func emit(root: String, label: String, suffix: String) throws {
            let head = root.lowercased()
            let tail = head.trimmingCharacters(in: .whitespaces)
            if label + suffix == "done" { return }
            try tail.write(toFile: root, atomically: true, encoding: .utf8)
        }
        """).isEmpty)
    }
}
