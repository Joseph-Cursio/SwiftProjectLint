//
//  SourcePatternDetectorProtocol.swift
//  SwiftProjectLint
//
//  Created by joe cursio on 7/14/25.
//
/// Protocol for pattern detection operations

public protocol SourcePatternDetectorProtocol {
    func detectPatterns(
        in sourceCode: String,
        filePath: String,
        categories: [PatternCategory]?
    ) -> [LintIssue]
    
    func clearCache()
}
