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
    func chunkingKernelIsCandidate() throws {
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
    func progressThrottleIsCandidate() throws {
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
}
