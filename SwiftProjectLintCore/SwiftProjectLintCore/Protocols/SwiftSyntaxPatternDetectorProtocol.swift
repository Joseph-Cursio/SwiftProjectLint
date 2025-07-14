//
//  SwiftSyntaxPatternDetectorProtocol.swift
//  SwiftProjectLint
//
//  Created by joe cursio on 7/14/25.
//
/// Protocol for pattern detection operations
@MainActor
public protocol SwiftSyntaxPatternDetectorProtocol {
    func detectPatterns(
        in sourceCode: String,
        filePath: String,
        categories: [PatternCategory]?
    ) async -> [LintIssue]
    
    func clearCache()
}
