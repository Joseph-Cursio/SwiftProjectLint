//
//  PatternVisitorRegistryProtocol.swift
//  SwiftProjectLint
//
//  Created by joe cursio on 7/14/25.
//
/// Protocol for pattern visitor registry operations
@MainActor
public protocol PatternVisitorRegistryProtocol {
    func register(pattern: SyntaxPattern)
    func register(patterns: [SyntaxPattern])
    func getVisitors(for category: PatternCategory) -> [PatternVisitor.Type]
    func getAllPatterns() -> [SyntaxPattern]
    func clear()
}
