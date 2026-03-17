//
//  ViewNameExtractorVisitor.swift
//  SwiftProjectLint
//
//  Created by Joseph Cursio on 7/9/25.
//
import SwiftSyntax

// MARK: - View Name Extractor Visitor

/// A visitor that extracts SwiftUI view names from a source file
class ViewNameExtractorVisitor: SyntaxVisitor {
    var viewNames: [String] = []
    
    override func visit(_ node: StructDeclSyntax) -> SyntaxVisitorContinueKind {
        // Check if this is a SwiftUI view
        if isSwiftUIView(node) {
            viewNames.append(node.name.text)
        }
        return .visitChildren
    }
    
} 
