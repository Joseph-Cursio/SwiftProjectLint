@testable import Core
import Foundation
import SwiftParser
@testable import SwiftProjectLintRules
import SwiftSyntax
import Testing

/// A fraction divides a count by a count; a rate divides a count by a duration. The law the rule
/// prints depends on telling them apart, and the first version could not.
@Suite("Extractable Total Kernel — a rate is not a progress fraction")
struct KernelFractionVersusRateTests {

    private func law(_ source: String) -> String {
        let visitor = ExtractableTotalKernelVisitor(patternCategory: .testability)
        let syntax = Parser.parse(source: source)
        let converter = SourceLocationConverter(fileName: "Logic.swift", tree: syntax)
        visitor.setSourceLocationConverter(converter)
        visitor.setFilePath("Logic.swift")
        visitor.walk(syntax)
        return visitor.detectedIssues
            .first { $0.ruleName == .extractableTotalKernel }?.message ?? "(no finding)"
    }

    private func claimsProgress(_ source: String) -> Bool {
        law(source).contains("progress should be monotonic")
    }

    // MARK: - Fractions keep the progress law

    /// The corpus's download loop. Both operands are converted counts.
    @Test func aCountOverACountIsProgress() {
        let source = """
        func download(_ bytes: Stream, expectedBytes: Int, report: (Double) -> Void) async throws {
            var data = Data()
            for try await byte in bytes {
                data.append(byte)
                guard expectedBytes > 0 else { continue }
                let progress = Double(data.count) / Double(expectedBytes)
                if progress >= 0.01 { report(progress) }
            }
        }
        """
        #expect(claimsProgress(source))
    }

    // The second fraction shape — `CGFloat(iteration) / CGFloat(max(iterations - 1, 1))` in
    // `GraphViewModel` — is verified by corpus measurement rather than a fixture here. A reduced
    // version of it does not qualify as a kernel at all (the surrounding loop is what makes it one),
    // and a test whose fixture reports nothing would have passed for the wrong reason in the
    // negative direction. Noted rather than faked.

    // MARK: - Rates do not

    /// **The defect.** `totalSeconds` is already a `Double`, so only the numerator is converted.
    /// Telling a tokens-per-second rate to stay within `0...1` sends a reader to clamp a number that
    /// must not be clamped.
    @Test func aCountOverADurationIsNotProgress() {
        let source = """
        func summarise(outcomes: [Outcome], write: (String) -> Void) async {
            let totalTokens = outcomes.map(\\.tokens).reduce(0, +)
            let totalSeconds = outcomes.map(\\.seconds).reduce(0, +)
            let rate = totalSeconds > 0 ? Double(totalTokens) / totalSeconds : 0
            write(String(rate))
        }
        """
        #expect(!claimsProgress(source))
    }

    /// The same shape one repository over, dividing chunks by a generation time.
    @Test func chunksOverElapsedTimeIsNotProgress() {
        let source = """
        func report(chunks: Int, genTime: Double, write: (String) -> Void) async {
            let rate = genTime > 0 ? Double(chunks) / genTime : 0
            write(String(rate))
        }
        """
        #expect(!claimsProgress(source))
    }

    // MARK: - The shape that chose the divisor rule

    /// An acceptance rate whose numerator is **already** a `Double`. A first attempt required a
    /// conversion on both sides and lost this — and lost the whole finding rather than just the
    /// label, because a kernel has to govern something and the fraction was what it governed.
    ///
    /// Reading only the divisor keeps it, which is why the rule reads only the divisor. This test
    /// began life asserting the opposite; it is inverted rather than deleted, because the measurement
    /// that flipped it is the reason the design is what it is.
    @Test func aDoubleOverAConvertedCountIsStillProgress() {
        let source = """
        func acceptance(accepted: Double, total: Int, write: (Double) -> Void) async {
            let overall = total > 0 ? accepted / Double(total) : 0
            write(overall)
        }
        """
        #expect(claimsProgress(source))
    }
}
