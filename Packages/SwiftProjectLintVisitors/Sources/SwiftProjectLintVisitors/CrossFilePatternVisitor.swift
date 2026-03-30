//
//  CrossFilePatternVisitor.swift
//  SwiftProjectLint
//
//  Created by Joseph Cursio on 7/9/25.
//
import SwiftSyntax

// MARK: - Cross-File Pattern Visitor Protocol

/// Protocol for pattern visitors that support cross-file analysis.
///
/// `CrossFilePatternVisitorProtocol` extends `PatternVisitorProtocol` to support analysis
/// that spans multiple files, such as duplicate detection or architectural
/// pattern analysis.
public protocol CrossFilePatternVisitorProtocol: PatternVisitorProtocol {
    /// The cached source files for cross-file analysis.
    var fileCache: [String: SourceFileSyntax] { get }
    
    /// Creates a new cross-file pattern visitor with access to the file cache.
    ///
    /// - Parameter fileCache: A dictionary mapping file paths to their parsed ASTs.
    init(fileCache: [String: SourceFileSyntax])
    
    /// Performs final analysis after all files have been processed.
    func finalizeAnalysis()
}
