//
//  CrossFileSwiftUIManagementVisitor.swift
//  SwiftProjectLint
//
//  Created by Joseph Cursio on 7/9/25.
//
import SwiftSyntax

// MARK: - Cross-File SwiftUI Management Visitor

/// A cross-file version of SwiftUIManagementVisitor that can analyze patterns across multiple files.
class CrossFileSwiftUIManagementVisitor: SwiftUIManagementVisitor, CrossFilePatternVisitorProtocol {
    let fileCache: [String: SourceFileSyntax]
    private var parentChildRelationships: [String: Set<String>] = [:] // parent -> children (direct containment)
    private var navigationRelationships: [String: Set<String>] = [:] // parent -> children (navigation)
    private var modalRelationships: [String: Set<String>] = [:] // parent -> children (modal presentations)

    required init(fileCache: [String: SourceFileSyntax]) {
        self.fileCache = fileCache
        super.init(patternCategory: .stateManagement)
        print("DEBUG: CrossFileSwiftUIManagementVisitor initialized with \(fileCache.count) files")
    }

    required init(patternCategory: PatternCategory) {
        self.fileCache = [:]
        super.init(viewMode: .sourceAccurate)
    }

    required init(viewMode: SyntaxTreeViewMode) {
        self.fileCache = [:]
        super.init(viewMode: viewMode)
    }

    override func finalizeAnalysis() {
    }

    func accept<T: PatternVisitorProtocol>(visitor: T) throws {
        // If the visitor understands this type, it can call its visit method.
        // If not, do nothing or throw if you want strict handling.
        // Here, just call walk on all cached source files with the visitor.
        for (_, sourceFile) in fileCache {
            visitor.walk(sourceFile)
        }
    }
}
