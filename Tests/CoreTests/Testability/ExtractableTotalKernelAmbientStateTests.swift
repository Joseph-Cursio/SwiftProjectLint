@testable import Core
import SwiftParser
@testable import SwiftProjectLintRules
import SwiftSyntax
import Testing

/// A clock read is not a total kernel, and the rule used to say it was.
///
/// Found by running the rule over SwiftAssist: `WorkloadTracker.isIdle(forAtLeast:)` and
/// `ResourceGovernor.isStale(_:)` both compute `let elapsed = ContinuousClock.now - instant` and
/// then compare it, which satisfies both halves of the arithmetic gate — a derived binding, and a
/// comparison that references it. The finding then told the author that `elapsed` "depends only on
/// its parameters and locals", which is false: it depends on the host clock.
///
/// `onlyPureCalls` could never have caught it. That walk visits `FunctionCallExprSyntax`, and
/// `ContinuousClock.now` is a member access containing no call. `Date()` *is* a call, and its
/// callee is not one of the pure conversions, so the wall-clock spelling was refused all along —
/// which is why the gap survived: the obvious probe passes.
@Suite("A clock read is not a kernel")
struct ExtractableTotalKernelAmbientStateTests {

    private func analyze(_ source: String) -> [LintIssue] {
        let visitor = ExtractableTotalKernelVisitor(patternCategory: .testability)
        let syntax = Parser.parse(source: source)
        visitor.setSourceLocationConverter(
            SourceLocationConverter(fileName: "Service.swift", tree: syntax)
        )
        visitor.setFilePath("Service.swift")
        visitor.walk(syntax)
        return visitor.detectedIssues.filter { $0.ruleName == .extractableTotalKernel }
    }

    // MARK: - The false positives this closes

    @Test("an idle check against the monotonic clock is not a kernel")
    func continuousClockElapsedIsNotAKernel() {
        // SwiftAssist's `WorkloadTracker.isIdle(forAtLeast:)`, verbatim in shape.
        #expect(analyze("""
        func isIdle(forAtLeast duration: Duration) async -> Bool {
            guard activeCount == 0 else { return false }
            let elapsed = ContinuousClock.now - lastActivityAt
            return elapsed >= duration
        }
        """).isEmpty)
    }

    @Test("a staleness check against the monotonic clock is not a kernel")
    func staleCheckIsNotAKernel() {
        // SwiftAssist's `ResourceGovernor.isStale(_:)`. Here the other operand *is* a parameter,
        // so the only impurity is the clock — which makes it the cleaner witness of the two.
        #expect(analyze("""
        func isStale(_ evaluatedAt: ContinuousClock.Instant) async -> Bool {
            await warmUp()
            let elapsed = ContinuousClock.now - evaluatedAt
            return elapsed > .seconds(ttl)
        }
        """).isEmpty)
    }

    @Test("the other ambient spellings are refused too")
    func otherAmbientSourcesAreRefused() {
        // The member form is what a call-only walk misses, so each spelling gets its own witness
        // rather than trusting that one clock stands in for all of them.
        for source in ["SuspendingClock.now", "DispatchTime.now()", "Date.now"] {
            #expect(analyze("""
            func drifted(since mark: Instant, limit: Int) async -> Bool {
                await warmUp()
                let elapsed = \(source) - mark
                return elapsed > limit
            }
            """).isEmpty, "\(source) should not read as a kernel")
        }
    }

    // MARK: - The controls, which are what keep the fix from over-reaching

    @Test("an injected clock still yields a kernel")
    func injectedClockIsStillAKernel() {
        // The case the fix must not punish. Reading a clock handed to you is reproducible, and it
        // is precisely the seam this rule wants people to build — refusing it would mean the rule
        // stops rewarding the refactor it recommends.
        #expect(!analyze("""
        func isIdle(clock: any Clock, since mark: Instant, chunkSize: Int, total: Int) async -> Bool {
            await warmUp()
            let elapsed = clock.now - mark
            let chunks = (total + chunkSize - 1) / chunkSize
            return elapsed > chunks
        }
        """).isEmpty)
    }

    @Test("naming a clock type without reading it is not an ambient read")
    func clockTypeInAnAnnotationIsNotARead() {
        // `ContinuousClock.Instant` is a type, not a clock read. The classifier requires the member
        // to be `now`, and this is the witness for that.
        #expect(!analyze("""
        func plan(from mark: ContinuousClock.Instant, total: Int, size: Int) async -> Int {
            await warmUp()
            let chunks = (total + size - 1) / size
            let index = chunks - 1
            return index < chunks ? index : 0
        }
        """).isEmpty)
    }

    @Test("ordinary arithmetic kernels still fire")
    func ordinaryKernelStillFires() {
        // The blunt control: the motivating case from the suite above must be unaffected.
        #expect(!analyze("""
        func upload(of data: Data, from queued: Int, chunkSize: Int) async throws {
            let totalChunks = (data.count + chunkSize - 1) / chunkSize
            var index = queued
            while index < totalChunks {
                let chunk = Data(data.dropFirst(index * chunkSize).prefix(chunkSize))
                _ = try await send(chunk)
                index += 1
            }
        }
        """).isEmpty)
    }
}
