import Core

/// Determines the appropriate exit code based on detected issues and the configured threshold.
struct ExitCodes {
    /// Exit code: no issues at or above the threshold severity.
    private static let clean: Int32 = 0
    /// Exit code: warnings found at or above threshold.
    private static let warnings: Int32 = 1
    /// Exit code: errors found.
    private static let errors: Int32 = 2

    /// Computes the exit code for a set of lint issues given a severity threshold.
    ///
    /// - Parameters:
    ///   - issues: The detected lint issues.
    ///   - threshold: The minimum severity that triggers a non-zero exit.
    /// - Returns: 0 if clean, 1 for warnings, 2 for errors.
    static func exitCode(for issues: [LintIssue], threshold: SeverityThreshold) -> Int32 {
        let hasErrors = issues.contains { $0.severity == .error }
        let hasWarnings = issues.contains { $0.severity == .warning }
        let hasInfo = issues.contains { $0.severity == .info }

        switch threshold {
        case .error:
            return hasErrors ? errors : clean
        case .warning:
            if hasErrors { return errors }
            if hasWarnings { return warnings }
            return clean
        case .info:
            if hasErrors { return errors }
            if hasWarnings || hasInfo { return warnings }
            return clean
        }
    }
}
