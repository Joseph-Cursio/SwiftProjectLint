//
//  PatternVisitor.swift
//  SwiftProjectLint
//
//  Created by Joseph Cursio on 7/9/25.
//
import SwiftSyntax

/// Protocol defining the interface for SwiftSyntax-based pattern visitors.
///
/// `PatternVisitorProtocol` provides a standardized way to implement pattern detection
/// using SwiftSyntax AST traversal. Each visitor is responsible for detecting
/// specific patterns within the Swift code and generating appropriate lint issues.
///
/// - Note: All pattern visitors should conform to this protocol and implement
///         the required methods for AST traversal and issue detection.
public protocol PatternVisitorProtocol: SyntaxVisitor {
    /// The collection of lint issues detected by this visitor during AST traversal.
    var detectedIssues: [LintIssue] { get }

    /// Resets the visitor's internal state, clearing any detected issues.
    /// This method should be called before reusing a visitor instance.
    func reset()

    /// The `SyntaxPattern` this visitor is responsible for detecting.
    var pattern: SyntaxPattern { get }

    /// Initializes the visitor with a `SyntaxPattern`.
    init(pattern: SyntaxPattern, viewMode: SyntaxTreeViewMode)
}

/// Represents a SwiftSyntax-based pattern definition for code analysis.
///
/// - Parameters:
///   - name: The display name of the pattern (used for reporting).
///   - visitor: The type of visitor responsible for detecting this pattern.
///   - severity: The level of importance of the detected issue.
///   - category: The logical category of the pattern.
///   - messageTemplate: A template for the issue message, supporting variable interpolation.
///   - suggestion: A recommended action or fix to resolve the detected issue.
///   - description: A detailed description of what this pattern detects.
