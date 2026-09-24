import Foundation
import SwiftProjectLintModels
import SwiftProjectLintVisitors
import SwiftSyntax

/// Detects a file that reaches through one collaborator for many of its members.
///
/// This is the Law of Demeter measured by *width* rather than depth. ``LawOfDemeterVisitor`` asks
/// how many hops a single chain takes; this asks how much of one object's shape a file has
/// internalised. The two find different things, and the difference is not academic: the largest
/// case this rule found — a stub emitter reading seven members of a `candidate` — is invisible to
/// any depth threshold, because every one of those chains is exactly two dots long.
///
/// Reaching for *one* member repeatedly is deliberately not reported. `site.location.filePath`
/// eight times is a missing forwarding accessor, a one-line fix with no design consequence.
/// Reaching for many different members is the thing that makes a change to the collaborator ripple
/// outward, which is what the Law of Demeter is actually about.
///
/// Cross-file, though the trigger is per-file, because the idiom filter needs to see every file:
/// a `(target, member-set)` that recurs *identically* across several files is a small value type
/// being used as designed, not several independent violations. Measured on SwiftInferProperties,
/// `identity.(display, normalized)` appeared in seven files — seven uses of a two-field type, and
/// zero problems.
final class WideReachThroughVisitor: CrossFileVisitorBase, CrossFilePatternVisitorProtocol {

    /// How many distinct members of one target a file must touch before this reports.
    private static let minDistinctMembers = 3

    /// Chain depth at which a member access is collected at all. 2 means `a.b.c` counts, so that
    /// the ordinary two-dot reach — the shape this rule exists to catch — is in scope.
    private static let minChainDepth = 2

    /// A `(target, member-set)` seen identically in at least this many files is an idiom.
    ///
    /// A real violation is idiosyncratic: one site that happens to have learned a shape. The same
    /// set of members read in the same way across several files is a type doing its job.
    private static let idiomFileThreshold = 3

    /// One member of one target, reached from one file. Lines are captured during the walk, while
    /// the node's own converter is installed.
    private struct Reach {
        let file: String
        let target: String
        let member: String
        let line: Int
    }

    private var reaches: [Reach] = []

    override func reset() {
        super.reset()
        reaches = []
    }

    override func visit(_ node: MemberAccessExprSyntax) -> SyntaxVisitorContinueKind {
        // Only the outermost access in a chain, so `a.b.c` is read once and not once per hop.
        if node.parent?.is(MemberAccessExprSyntax.self) == true { return .visitChildren }
        // A chain that is the callee of a call is a method invocation, not a reach for data.
        if node.parent?.is(FunctionCallExprSyntax.self) == true { return .visitChildren }
        // Test and fixture files are full of deliberately shaped sample code.
        if isTestOrFixtureFile() { return .visitChildren }

        guard let (components, _) = DemeterChainFilter.qualifyingChain(
            from: node, minChainDepth: Self.minChainDepth
        ), components.count >= 2 else {
            return .visitChildren
        }

        // The target is the thing being reached into — the penultimate hop. The member is what was
        // asked of it. `inputs.candidate.carrierKind` is the member `carrierKind` of `candidate`.
        reaches.append(
            Reach(
                file: currentFilePath,
                target: components[components.count - 2],
                member: components[components.count - 1],
                line: getLineNumber(for: Syntax(node))
            )
        )
        return .visitChildren
    }

    func finalizeAnalysis() {
        var membersByPair: [Pair: Set<String>] = [:]
        var lineByPair: [Pair: Int] = [:]
        for reach in reaches {
            let pair = Pair(file: reach.file, target: reach.target)
            membersByPair[pair, default: []].insert(reach.member)
            lineByPair[pair] = min(lineByPair[pair] ?? reach.line, reach.line)
        }

        let idioms = idiomaticSignatures(in: membersByPair)

        for pair in membersByPair.keys.sorted() {
            guard let members = membersByPair[pair], members.count >= Self.minDistinctMembers
            else { continue }
            guard !idioms.contains(Signature(target: pair.target, members: members.sorted()))
            else { continue }
            emit(pair: pair, members: members.sorted(), line: lineByPair[pair] ?? 1)
        }
    }

    /// The `(target, member-set)` signatures that recur across enough files to be idiom, not fault.
    private func idiomaticSignatures(in membersByPair: [Pair: Set<String>]) -> Set<Signature> {
        var filesPerSignature: [Signature: Int] = [:]
        for pair in membersByPair.keys.sorted() {
            guard let members = membersByPair[pair] else { continue }
            let signature = Signature(target: pair.target, members: members.sorted())
            filesPerSignature[signature, default: 0] += 1
        }
        return Set(
            filesPerSignature
                .filter { $0.value >= Self.idiomFileThreshold }
                .keys
        )
    }

    private func emit(pair: Pair, members: [String], line: Int) {
        let memberList = members.joined(separator: ", ")
        addIssue(
            severity: .info,
            message: "This file reaches through '\(pair.target)' for \(members.count) of its "
                + "members (\(memberList)) — it depends on '\(pair.target)'s internal shape, so a "
                + "change there ripples here.",
            filePath: pair.file,
            lineNumber: line,
            suggestion: "Move the logic that needs these members onto '\(pair.target)', or pass "
                + "the specific values this file needs.",
            ruleName: .wideReachThrough
        )
    }

    /// One file's reaching into one target.
    private struct Pair: Hashable, Comparable {
        let file: String
        let target: String

        static func < (lhs: Self, rhs: Self) -> Bool {
            (lhs.file, lhs.target) < (rhs.file, rhs.target)
        }
    }

    /// A target and the exact set of members asked of it, for recognising a repeated idiom.
    private struct Signature: Hashable {
        let target: String
        let members: [String]
    }
}
