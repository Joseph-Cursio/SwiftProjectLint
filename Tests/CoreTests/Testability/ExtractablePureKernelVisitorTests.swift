@testable import Core
import Foundation
import SwiftParser
@testable import SwiftProjectLintRules
import SwiftSyntax
import Testing

/// The pure function trapped inside an impure method.
///
/// `pureFunctionCandidate` sees declarations and `pureClosureCandidate` sees closures. Neither can
/// see arithmetic with no boundary drawn around it, inlined in a method that also does I/O — which
/// is where two of MacCloud's three real bugs live.
///
/// **The silences in this suite matter more than the fires.** A kernel has no syntactic boundary, so
/// the rule's whole worth is its precision; the acceptance set below was built by hand-classifying
/// all 85 functions in the fixture app before a line of the rule was written.
@Suite("Arithmetic trapped inside an impure method")
struct ExtractablePureKernelVisitorTests {

    private func analyze(_ source: String, filePath: String = "Service.swift") -> [LintIssue] {
        let visitor = ExtractablePureKernelVisitor(patternCategory: .testability)
        let syntax = Parser.parse(source: source)
        visitor.setSourceLocationConverter(
            SourceLocationConverter(fileName: filePath, tree: syntax)
        )
        visitor.setFilePath(filePath)
        visitor.walk(syntax)
        return visitor.detectedIssues.filter { $0.ruleName == .extractablePureKernel }
    }

    // MARK: - The motivating case

    @Test("the chunking arithmetic inside an async upload is a candidate")
    func chunkingKernelIsCandidate() {
        // MacCloud's `uploadRemainingChunks`, and the reason this rule exists. How many chunks,
        // where chunk n starts, how far along we are: a function of (data.count, chunkSize, index)
        // and nothing else — welded to a method that needs a live session and a server, so no test
        // can reach it. Two of the app's three real bugs live in these four lines.
        let issues = analyze("""
        func uploadRemainingChunks(of data: Data, from queued: Int, chunkSize: Int) async throws {
            let totalChunks = (data.count + chunkSize - 1) / chunkSize
            var index = queued
            while index < totalChunks {
                let chunk = Data(data.dropFirst(index * chunkSize).prefix(chunkSize))
                _ = try await uploadChunk(chunk)
                index += 1
                progressHandler?(Double(index) / Double(totalChunks))
            }
        }
        """)

        #expect(issues.count == 1)
        #expect(issues.first?.message.contains("totalChunks") == true)
        #expect(issues.first?.message.contains("tile the whole exactly") == true)
    }

    @Test("a progress throttle inside a byte stream is a candidate")
    func progressThrottleIsCandidate() {
        // MacCloud's `collect`, which the fix plan did not know about — found by hand-classifying
        // the app before writing the rule. It is the *same defect family* as the known chunking bug:
        // if the server omits Content-Length, `expectedBytes <= 0` and progress is never reported at
        // all. Generalising a bug class is worth more than re-finding one bug.
        let issues = analyze("""
        func collect(_ bytes: URLSession.AsyncBytes, expecting expectedBytes: Int64) async throws -> Data {
            var data = Data()
            var lastReported = 0.0
            for try await byte in bytes {
                data.append(byte)
                guard expectedBytes > 0 else { continue }
                let progress = Double(data.count) / Double(expectedBytes)
                if progress - lastReported >= 0.01 {
                    lastReported = progress
                    progressHandler(progress)
                }
            }
            return data
        }
        """)

        #expect(issues.count == 1)
        #expect(issues.first?.message.contains("terminate at 1.0") == true)
    }

    // MARK: - The three gates

    @Test("a pure function has no trapped kernel — it IS the kernel")
    func pureFunctionIsNotReported() {
        // Gate 1, and the hand-audit is what found it. Without this, the rule fires on
        // `isValidFolderName` — an already-named pure function with nothing to extract, which
        // `pureFunctionCandidate` already seeds. A rule that re-reports another rule's findings
        // teaches the reader the two disagree.
        #expect(analyze("""
        func chunkCount(of byteCount: Int, chunkSize: Int) -> Int {
            let total = (byteCount + chunkSize - 1) / chunkSize
            return total > 0 ? total : 1
        }
        """).isEmpty)
    }

    @Test("a kernel inside a closure belongs to the closure rule, not this one")
    func kernelInsideAClosureIsNotDoubleReported() {
        // Gate 2. `pureClosureCandidate` reports this predicate already. Reporting it twice would be
        // one finding wearing two hats.
        #expect(analyze("""
        func loadFiles(from store: Store) async throws {
            let all = try await store.fetch()
            let children = all.filter { file in
                let depth = file.path.count - currentPath.count
                return depth > 0 && depth < 2
            }
            self.files = children
        }
        """).isEmpty)
    }

    @Test("arithmetic that is merely stored is not a kernel")
    func arithmeticWithoutAGoverningUseIsNotReported() {
        // Gate 3, and the boundary with the state-machine template. MacCloud's `navigateUp` computes
        // a parent path with real logic — but the result is *assigned*, never used as a bound, an
        // index, a slice or a fraction. That shape is a state-machine law (`up ∘ down == id`), and it
        // belongs to a different template. This rule staying quiet here is correct, not a miss.
        #expect(analyze("""
        func navigateUp() async {
            let components = currentPath.split(separator: "/")
            let parent = components.dropLast().joined(separator: "/")
            currentPath = "/" + parent + "/"
            await loadFiles()
        }
        """).isEmpty)
    }

    // MARK: - Silences (the acceptance set, from the 85-function hand audit)

    @Test("a request builder has no separable kernel")
    func requestBuildingIsNotReported() {
        #expect(analyze("""
        func login(email: String, password: String) async throws -> User {
            var request = createRequest(endpoint: "/auth/login", method: "POST")
            request.httpBody = try JSONEncoder().encode(Credentials(email: email, password: password))
            let (data, response) = try await session.data(for: request)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else {
                throw MacCloudError.unauthorized
            }
            return try decoder.decode(User.self, from: data)
        }
        """).isEmpty)
    }

    @Test("a retry counter compared to a constant is not a kernel")
    func retryCounterIsNotReported() {
        // One binding, no arithmetic feeding the comparison. `retries < maxRetries` decides nothing
        // a generator could break.
        #expect(analyze("""
        func uploadChunkWithRetry(index: Int, chunk: Data) async throws -> Response {
            var retries = 0
            while true {
                do {
                    return try await uploadChunk(index: index, data: chunk)
                } catch let error as URLError {
                    guard retries < Self.maxChunkRetries else { throw error }
                    retries += 1
                }
            }
        }
        """).isEmpty)
    }

    @Test("test files are skipped")
    func testFilesAreSkipped() {
        #expect(analyze("""
        func uploadRemainingChunks(of data: Data, chunkSize: Int) async throws {
            let totalChunks = (data.count + chunkSize - 1) / chunkSize
            var index = 0
            while index < totalChunks {
                _ = try await upload(data.dropFirst(index * chunkSize).prefix(chunkSize))
                index += 1
            }
        }
        """, filePath: "ServiceTests.swift").isEmpty)
    }

    // MARK: - The advice names the tiler shape when one is present (B16)

    /// **A kernel with slicing arithmetic must tell the reader to extract a TILER, not just "the
    /// arithmetic."** Cold-reader walks measured the cost of the vague advice: given chunking math,
    /// readers reliably lift the scalar chunk *count*, which carries no tiling law — so the
    /// `partition` law that catches the resume-counter and empty-payload bugs is never proposed, and
    /// the bug is one method away. The suggestion now names the index-to-slice shape.
    @Test("a slicing kernel's advice names the index-to-slice tiler shape")
    func slicingKernelSuggestsATiler() throws {
        let issue = try #require(analyze("""
        func uploadRemainingChunks(of data: Data, from queued: Int, chunkSize: Int) async throws {
            let totalChunks = (data.count + chunkSize - 1) / chunkSize
            var index = queued
            while index < totalChunks {
                let chunk = Data(data.dropFirst(index * chunkSize).prefix(chunkSize))
                _ = try await uploadChunk(chunk)
                index += 1
                progressHandler?(Double(index) / Double(totalChunks))
            }
        }
        """).first)

        let suggestion = try #require(issue.suggestion)
        #expect(suggestion.contains("maps a part INDEX to its slice"))
        #expect(suggestion.contains("byteRange(ofChunk"))
        // And it warns off the scalar the readers kept extracting.
        #expect(suggestion.contains("count"))
    }

    /// A kernel that is a **fraction with no slicing** — a progress throttle — keeps the generic
    /// advice: there is no tiler shape to name, so naming one would be cargo-culting.
    @Test("a fraction-only kernel keeps the generic advice, not the tiler shape")
    func fractionOnlyKernelKeepsGenericAdvice() throws {
        let issue = try #require(analyze("""
        func stream(_ received: Int, of expected: Int) async throws {
            let fraction = Double(received) / Double(expected)
            if fraction - lastReported >= 0.01 {
                progressHandler?(fraction)
                _ = try await flush()
            }
        }
        """).first)

        let suggestion = try #require(issue.suggestion)
        #expect(suggestion.contains("Extract the arithmetic into a value type"))
        #expect(suggestion.contains("maps a part INDEX to its slice") == false)
    }

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
