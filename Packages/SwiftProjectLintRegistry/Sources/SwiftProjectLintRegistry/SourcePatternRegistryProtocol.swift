//
//  SourcePatternRegistryProtocol.swift
//  SwiftProjectLint
//
//  Created by joe cursio on 7/14/25.
//
import SwiftProjectLintModels
import SwiftProjectLintVisitors

/// Protocol for SwiftSyntax pattern registry operations

public protocol SourcePatternRegistryProtocol {
    func initialize()
    func getPatterns(for category: PatternCategory) -> [SyntaxPattern]
    func getAllPatterns() -> [SyntaxPattern]
    func register(pattern: SyntaxPattern)
    func register(patterns: [SyntaxPattern])
}
