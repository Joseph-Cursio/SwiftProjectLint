import SwiftProjectLintModels
import SwiftProjectLintVisitors
import SwiftSyntax

/// Operations that identify a **path**, as opposed to any string.
///
/// `Collector.pathCalls` is the gate for the *shape*, and it is deliberately broad —
/// `lowercased`, `split`, `joined`, `trimmingCharacters` are string operations that happen to be
/// how paths get built. This narrower set is what licenses the *advice* to talk about a root.
///
/// **Looked for across the whole body, not only in the derived bindings.** The canonical fixture
/// is `DirectoryScanner.scanSync`, and its two bindings are
/// `prefix = rootPath.hasSuffix("/") ? rootPath : rootPath + "/"` and
/// `relativePath = item.hasPrefix(prefix) ? String(item.dropFirst(prefix.count)) : item` — both
/// built entirely from generic string operations. What makes it a path derivation is the
/// `(relativePath as NSString).lastPathComponent` on the next line. A binding-scoped check gets
/// the most canonical case in the corpus wrong, which is how this scope was chosen.
enum PathEvidence {

    static let names: Set<String> = [
        "appendingPathComponent", "appendingPathExtension", "deletingLastPathComponent",
        "deletingPathExtension", "standardizingPath", "standardizedFileURL",
        "lastPathComponent", "pathExtension", "pathComponents", "relativePath",
        "resolvingSymlinksInPath", "absoluteString",
    ]

    /// Deliberately descends into closures, unlike the kernel walk. A closure body belongs to a
    /// different rule *as a kernel*; as **evidence that this method handles paths** it counts —
    /// `excludedPath.contains { url.deletingLastPathComponent().relativePath.hasPrefix($0) }` is
    /// the whole shape the path advice is for, and all of it sits inside the closure.
    static func occurs(in node: Syntax) -> Bool {
        if let member = node.as(MemberAccessExprSyntax.self),
           names.contains(member.declName.baseName.text) {
            return true
        }
        for child in node.children(viewMode: .sourceAccurate) where occurs(in: child) {
            return true
        }
        return false
    }
}

/// The pure function trapped inside an impure method.
///
/// `pureFunctionCandidate` points at a whole declaration and `pureClosureCandidate` points at a
/// closure. Neither can see the third and most valuable shape: **arithmetic with no boundary drawn
/// around it**, inlined in a method that also does network or disk I/O.
///
///     private func uploadRemainingChunks(of data: Data, …) async throws -> … {
///         let totalChunks = (data.count + chunkSize - 1) / chunkSize
///         var index = current.queuedChunks
///         while index < totalChunks {
///             let chunk = Data(data.dropFirst(index * chunkSize).prefix(chunkSize))
///             _ = try await uploadChunkWithRetry(…)          // ← the impurity
///             index += 1
///             progressHandler?(Double(index) / Double(totalChunks))
///         }
///     }
///
/// How many chunks; where chunk *n* starts; how far along we are. That is a function of
/// `(data.count, chunkSize, index)` and nothing else — it touches no network, no disk, no clock. But
/// it is welded to a `private async throws` method that needs a live session and a server, so *no
/// test can reach it*, and it is where two of this app's three real bugs live: an unclamped
/// server-supplied resume index that completes a partial upload, and an empty payload whose progress
/// never reaches `1.0`.
///
/// The rule reports the **refactor**, not a smell: lift the arithmetic into a value type and it
/// becomes a function you can generate inputs for — the chunks should tile the payload exactly, and
/// progress should terminate at 1.0.
///
/// **Three gates keep it from firing on everything**, and each one was put there by a finding:
///
/// - **The enclosing function must be impure.** Otherwise the rule re-reports every pure function in
///   the codebase, which `pureFunctionCandidate` already owns. A hand-audit of 85 functions caught
///   this: without the gate, the rule fires on `isValidFolderName`, which is *already* a named pure
///   function with nothing to extract.
/// - **Closure bodies are skipped.** `pureClosureCandidate` owns those, and a kernel that lives
///   wholly inside a `filter` predicate is that rule's finding, reported once.
/// - **A derivation must feed a decision.** A derived value that is merely *stored* is not a kernel
///   — it has to govern something: a loop bound, an index, a slice range, a comparison, or a
///   progress fraction. This is the clause that separates chunking math from a local variable
///   someone extracted for readability, and it is why `navigateUp`'s pure path arithmetic is
///   deliberately *not* reported here (its result is assigned, not used as a bound) — that shape is
///   a state-machine law, and it belongs to a different template.
///
/// ## Two shapes, because one of them was found by the rule scoring zero
///
/// The gates above describe the **arithmetic** shape. It was the only shape for as long as the rule
/// was only ever pointed at an app whose bugs were chunking math — and then the rule was run over a
/// 60k-line linter and reported **nothing at all**. Not "this code is clean": the linter's impure
/// methods enumerate directories and derive paths, and a path kernel has no operator reaching a
/// bound, so every gate walked past it. `dropFirst(prefix.count)` is a slice with no arithmetic in
/// it anywhere.
///
/// So there is a second shape: a **path/string derivation that governs a decision**. Two strings
/// derived and chained, then used to slice, to compare, or to look up. Its law is a round-trip and
/// an idempotent normalisation rather than a tiling, and its bugs are off-by-one prefixes rather
/// than off-by-one counts — including both of the bugs this project's own property-test road test
/// found.
///
/// Admitting it narrows the third gate rather than widening it: a derived *display string* still
/// does not fire, because it governs nothing. What changed is that "governs" now includes deciding
/// with a string, not only bounding a loop with a number.
///
/// `info` severity; opt-in. Reports a refactor, not a defect.
final class ExtractableTotalKernelVisitor: BasePatternVisitor, PackagePurityConsumer {

    /// `isPure(function)`, the method's first gate.
    static let packagePurityInputs: PackagePurityInputs = [.oracle]

    private var fileIsTestOrFixture = false
    private let purityInferrer = PurityInferrer()

    required init(pattern: SyntaxPattern, viewMode: SyntaxTreeViewMode = .sourceAccurate) {
        super.init(pattern: pattern, viewMode: viewMode)
    }

    override func setFilePath(_ filePath: String) {
        super.setFilePath(filePath)
        fileIsTestOrFixture = isTestOrFixtureFile()
    }

    override func visit(_ node: FunctionDeclSyntax) -> SyntaxVisitorContinueKind {
        guard !fileIsTestOrFixture,
              let body = node.body,
              // Gate 1: a *pure* function has no trapped kernel — it IS the kernel, and
              // `pureFunctionCandidate` reports it when a test can compare its result.
              !purityInferrer.isPure(node) else {
            return .visitChildren
        }

        let kernel = KernelScan(body: body)
        guard kernel.isWorthExtracting else { return .visitChildren }

        addIssue(
            severity: .info,
            message: "A total kernel is trapped in this impure method — \(kernel.summary) depend "
                + "only on its parameters and locals, and nothing else in the method reaches them. "
                + "Lift them into a value type and they become property-testable: \(kernel.law)",
            filePath: getFilePath(for: Syntax(kernel.anchor)),
            lineNumber: getLineNumber(for: Syntax(kernel.anchor)),
            suggestion: kernel.suggestion,
            ruleName: .extractableTotalKernel,
            symbol: node.name.text,
            role: kernel.role
        )
        return .visitChildren
    }
}
