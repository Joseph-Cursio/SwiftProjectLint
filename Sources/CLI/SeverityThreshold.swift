import ArgumentParser
import Core

/// The minimum severity level that triggers a non-zero exit code.
enum SeverityThreshold: String, ExpressibleByArgument, CaseIterable {
    case error
    case warning
    case info

    /// Returns the corresponding IssueSeverity from Core.
    var issueSeverity: IssueSeverity {
        switch self {
        case .error: return .error
        case .warning: return .warning
        case .info: return .info
        }
    }
}
