//
//  IssueSeverity.swift
//  SwiftProjectLint
//
//  Created by Joseph Cursio on 7/9/25.
//


/// Represents the severity level of a lint issue detected by the linter.
///
/// Use `error` for serious problems that may cause project malfunction, `warning` for potential problems or code style issues,
/// and `info` for suggestions or informational notes that do not require immediate attention.
///
/// - Cases:
///   - error: Indicates a critical issue that should be fixed to ensure correct project behavior.
///   - warning: Indicates a potential issue or code style concern that may not break the project but is recommended to address.
///   - info: Provides informational messages or suggestions for improving code quality or consistency.
///
/// - SeeAlso: `LintIssue`
public enum IssueSeverity: String, Codable, Sendable {
    case error
    case warning
    case info
}
