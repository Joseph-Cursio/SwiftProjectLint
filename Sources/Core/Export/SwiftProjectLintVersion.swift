import Foundation

/// The SwiftProjectLint release, reported by `--version` and in the JSON report.
///
/// Bump it in the release commit, and tag that commit with the same version,
/// so a report can be traced to the code that produced it.
public enum SwiftProjectLintVersion {
    /// This build's release.
    public static let current = "1.1.0"
}
