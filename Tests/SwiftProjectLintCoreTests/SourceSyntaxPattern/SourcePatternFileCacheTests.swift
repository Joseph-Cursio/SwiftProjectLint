//
//  SourcePatternFileCacheTests.swift
//  SwiftProjectLint
//
//  Created by Joseph Cursio on 7/15/25.
//
import Testing
import Foundation
@testable import SwiftProjectLintCore

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

@MainActor
final class SourcePatternFileCacheTests {
    // MARK: - File Cache Characterization
    
    @Test func characterizeFileCacheBasicBehavior() throws {
        let detector = SourcePatternDetector()
        
        let file1Content = """
        import SwiftUI
        struct View1: View {
            @State var test: Bool = false
            var body: some View { Text("View 1") }
        }
        """
        
        let file2Content = """
        import SwiftUI
        struct View2: View {
            @State var test: Bool = false
            var body: some View { Text("View 2") }
        }
        """
        
        // Analyze first file
        let issues1 = detector.detectPatterns(in: file1Content, filePath: "/View1.swift")
        
        // Analyze second file
        let issues2 = detector.detectPatterns(in: file2Content, filePath: "/View2.swift")
        
        print("📊 File Cache Basic Behavior:")
        print("   File 1 analysis: \(issues1.count) issues")
        print("   File 2 analysis: \(issues2.count) issues")
        print("   Cache behavior: Single-file analysis per call")
        
    }
    
    @Test func characterizeCacheClearingBehavior() throws {
        let detector = SourcePatternDetector()
        
        let testContent = """
        import SwiftUI
        struct TestView: View {
            @State var test: Bool = false
            var body: some View { Text("Test") }
        }
        """
        
        // Analyze file
        let issuesBefore = detector.detectPatterns(in: testContent, filePath: "/Test.swift")
        
        // Clear cache
        detector.clearCache()
        
        // Analyze same content again
        let issuesAfter = detector.detectPatterns(in: testContent, filePath: "/Test.swift")
        
        print("📊 Cache Clearing Behavior:")
        print("   Issues before cache clear: \(issuesBefore.count)")
        print("   Issues after cache clear: \(issuesAfter.count)")
        print("   Cache clearing appears to work without affecting analysis")
        
        #expect(issuesBefore.count == issuesAfter.count, "Cache clearing should not affect analysis results")
    }
    
 }
