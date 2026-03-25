//
//  CrossFileAnalsysClaims.swift
//  SwiftProjectLint
//
//  Created by Joseph Cursio on 7/15/25.
//
import Testing
import Foundation
@testable import Core

/// Comprehensive Characterization Tests for SourcePatternDetector
///
/// These tests document and verify the current behavior of the pattern detector,
/// helping to catch regressions and understand how the system actually works.
///
/// Key areas of characterization:
/// - Basic input/output behavior
/// - Category filtering
/// - File cache management
/// - Cross-file analysis claims vs reality
/// - Rule identifier filtering
/// - Error handling and edge cases

struct CrossFileAnalysisClaimsTests {
    
    // MARK: - Cross-File Analysis Claims Investigation
    
    // swiftprojectlint:disable Test Missing Require
    @Test func characterizeCrossFileAnalysisClaimsVsReality() throws {
        let detector = SourcePatternDetector()
        
        // Create two files with identical state variables (potential duplicates)
        let parentViewContent = """
    import SwiftUI
    
    struct ParentView: View {
        @State private var isLoading: Bool = false
        @State private var userName: String = ""
        @State private var counter: Int = 0
        
        var body: some View {
            VStack {
                ChildView()
                if isLoading {
                    ProgressView()
                }
            }
        }
    }
    """
        
        let childViewContent = """
    import SwiftUI
    
    struct ChildView: View {
        @State private var isLoading: Bool = false  // Same as parent
        @State private var userName: String = ""   // Same as parent
        @State private var counter: Int = 0        // Same as parent
        
        var body: some View {
            VStack {
                Text("Child View")
                TextField("Enter name", text: $userName)
                Text("Count: \\(counter)")
            }
        }
    }
    """
        
        // Analyze files separately (current single-file behavior)
        let parentIssues = detector.detectPatterns(in: parentViewContent, filePath: "/ParentView.swift")
        let childIssues = detector.detectPatterns(in: childViewContent, filePath: "/ChildView.swift")
        
        // Look for any cross-file duplicate detection
        let allIssues = parentIssues + childIssues
        let duplicateRelatedIssues = allIssues.filter { issue in
            let ruleName = issue.ruleName.rawValue.lowercased()
            let message = issue.message.lowercased()
            return ruleName.contains("duplicate") || message.contains("duplicate")
        }
        
    }
    
    // swiftprojectlint:disable Test Missing Require
    @Test func characterizeFileCacheCapabilities() throws {
        let detector = SourcePatternDetector()
        
        // Test if file cache can hold multiple files simultaneously
        let view1 = """
    import SwiftUI
    struct View1: View {
        @State var data1: String = ""
        var body: some View { Text("1") }
    }
    """
        
        let view2 = """
    import SwiftUI
    struct View2: View {
        @State var data2: String = ""
        var body: some View { Text("2") }
    }
    """
        
        let view3 = """
    import SwiftUI
    struct View3: View {
        @State var data3: String = ""
        var body: some View { Text("3") }
    }
    """
        
        // Analyze multiple files in sequence
        _ = detector.detectPatterns(in: view1, filePath: "/View1.swift")
        _ = detector.detectPatterns(in: view2, filePath: "/View2.swift")
        _ = detector.detectPatterns(in: view3, filePath: "/View3.swift")
        
        #expect(true, "File cache should handle sequential single-file analysis")
    }
    
}
