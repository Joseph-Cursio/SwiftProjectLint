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

extension CrossFilePatternVisitorProtocol {

    /// Single-file convenience, equivalent to `finalizeAnalysis()`. When a visitor is driven
    /// outside the `CrossFileAnalysisEngine` — most often a unit test — the caller walks each
    /// source once and then calls `analyze()`, so the flow reads `walk(source); analyze()`.
    /// Production analysis goes through `finalizeAnalysis()`, which the engine invokes once every
    /// file has been walked.
    ///
    /// Hoisted here from five idempotency visitors that each carried the identical forwarder
    /// (flagged by the Hoistable Conformer Member rule dogfooding this project).
    public func analyze() {
        finalizeAnalysis()
    }
}
