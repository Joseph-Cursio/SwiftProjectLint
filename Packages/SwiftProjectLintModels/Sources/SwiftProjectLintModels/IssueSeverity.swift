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
/// `CaseIterable` so that presentation mappings over severity can be checked exhaustively rather
/// than one example per case. A three-case switch is exactly where a fourth case gets folded into
/// an existing branch, and only a test that iterates `allCases` notices.
public enum IssueSeverity: String, Codable, Sendable, CaseIterable {
    case error
    case warning
    case info
}
