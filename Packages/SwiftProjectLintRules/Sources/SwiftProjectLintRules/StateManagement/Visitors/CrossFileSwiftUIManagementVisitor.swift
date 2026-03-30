//
//  CrossFileSwiftUIManagementVisitor.swift
//  SwiftProjectLint
//
//  Created by Joseph Cursio on 7/9/25.
//
import SwiftProjectLintModels
import SwiftProjectLintRegistry
import SwiftProjectLintVisitors
import SwiftSyntax

// MARK: - Cross-File SwiftUI Management Visitor

/// A cross-file version of SwiftUIManagementVisitor that can analyze patterns across multiple files.
class CrossFileSwiftUIManagementVisitor: SwiftUIManagementVisitor, CrossFilePatternVisitorProtocol {
    let fileCache: [String: SourceFileSyntax]

    required init(fileCache: [String: SourceFileSyntax]) {
        self.fileCache = fileCache
        super.init(pattern: BasePatternVisitor.placeholderPattern, viewMode: .sourceAccurate)
    }

    required init(pattern: SyntaxPattern, viewMode: SyntaxTreeViewMode = .sourceAccurate) {
        self.fileCache = [:]
        super.init(pattern: pattern, viewMode: viewMode)
    }

    override func finalizeAnalysis() {
    }

}
