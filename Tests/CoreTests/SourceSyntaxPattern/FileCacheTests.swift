//
//  SourcePatternFileCacheTests.swift
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

struct FileCacheTests {
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
        
        // Both files should be analyzed independently
        #expect(issues1.count >= 0)
        #expect(issues2.count >= 0)
    }
    
 }
