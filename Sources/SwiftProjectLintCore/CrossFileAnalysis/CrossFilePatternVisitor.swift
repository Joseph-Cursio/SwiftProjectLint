//
//  CrossFilePatternVisitor.swift
//  SwiftProjectLint
//
//  Created by Joseph Cursio on 7/9/25.
//
import SwiftSyntax

// MARK: - Visitable Protocol

/// Protocol that defines objects which can be visited by visitors.
///
/// This protocol is used to ensure type safety in the visitor pattern implementation,
/// allowing for consistent cross-file analysis and multiple visitor types.
protocol Visitable {
    /// Accepts a visitor and allows it to perform operations on this object.
    ///
    /// - Parameter visitor: The visitor that will operate on this object.
    func accept<T: PatternVisitorProtocol>(visitor: T) throws
}

// MARK: - Cross-File Pattern Visitor Protocol

/// Protocol for pattern visitors that support cross-file analysis.
///
/// `CrossFilePatternVisitorProtocol` extends `PatternVisitorProtocol` to support analysis
/// that spans multiple files, such as duplicate detection or architectural
/// pattern analysis.
protocol CrossFilePatternVisitorProtocol: PatternVisitorProtocol, Visitable {
    /// The cached source files for cross-file analysis.
    var fileCache: [String: SourceFileSyntax] { get }
    
    /// Creates a new cross-file pattern visitor with access to the file cache.
    ///
    /// - Parameter fileCache: A dictionary mapping file paths to their parsed ASTs.
    init(fileCache: [String: SourceFileSyntax])
    
    /// Performs final analysis after all files have been processed.
    func finalizeAnalysis()
}
