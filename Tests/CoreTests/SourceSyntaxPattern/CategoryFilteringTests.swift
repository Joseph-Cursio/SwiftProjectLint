//
//  SourcePatternCategoryFilteringTests.swift
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

struct CategoryFilteringTests {
    
    // MARK: - Category Filtering Characterization
    
    @Test func characterizeStateManagementCategoryFiltering() throws {
        let detector = SourcePatternDetector()
        let stateCode = """
        import SwiftUI
        
        struct StateTestView: View {
            @State private var isVisible: Bool = false
            @State private var data: [String] = []
            @State private var unusedVar: Int = 42
            
            var body: some View {
                VStack {
                    if isVisible {
                        ForEach(data, id: \\.self) { item in
                            Text(item)
                        }
                    }
                }
            }
        }
        """
        
        // Test with state management category only
        let stateIssues = detector.detectPatterns(
            in: stateCode,
            filePath: "/StateTest.swift",
            categories: [.stateManagement]
        )
        
        // Test with all categories
        let allIssues = detector.detectPatterns(
            in: stateCode,
            filePath: "/StateTest.swift",
            categories: nil
        )
        
        print("📊 State Management Category Filtering:")
        print("   Input: View with state variables and potential unused state")
        print("   State category only: \(stateIssues.count) issues")
        print("   All categories: \(allIssues.count) issues")
        print("   State-specific issues:")
        for issue in stateIssues {
            print("     - \(issue.ruleName.rawValue): \(issue.message)")
        }
        
        #expect(allIssues.count >= stateIssues.count, "All categories should include at least state issues")
    }
    
    @Test func characterizePerformanceCategoryFiltering() throws {
        let detector = SourcePatternDetector()
        let performanceCode = """
        import SwiftUI
        
        struct PerformanceTestView: View {
            var body: some View {
                VStack {
                    ForEach(0..<1000) { index in
                        VStack {
                            Text("Item \\(index)")
                            Text("Description for item \\(index)")
                            Text("Additional details for \\(index)")
                            HStack {
                                Button("Action 1") { }
                                Button("Action 2") { }
                                Button("Action 3") { }
                            }
                        }
                    }
                }
            }
        }
        """
        
        let performanceIssues = detector.detectPatterns(
            in: performanceCode,
            filePath: "/PerformanceTest.swift",
            categories: [.performance]
        )
        
        print("📊 Performance Category Filtering:")
        print("   Input: View with potentially expensive nested loops")
        print("   Performance issues found: \(performanceIssues.count)")
        for issue in performanceIssues {
            print("     - Line \(issue.lineNumber): \(issue.ruleName.rawValue)")
        }
        
    }
    
    @Test func characterizeMultipleCategoryFiltering() throws {
        let detector = SourcePatternDetector()
        let multiCategoryCode = """
        import SwiftUI
        
        struct MultiCategoryView: View {
            @State private var isLoading: Bool = false
            @State private var unusedState: String = ""
            
            var body: some View {
                VStack {
                    ForEach(0..<100) { index in
                        Text("Item \\(index)")
                    }
                    
                    Button("Tap") {
                        isLoading.toggle()
                    }
                }
            }
        }
        """
        
        let multipleCategories: [PatternCategory] = [.stateManagement, .performance, .accessibility]
        let issues = detector.detectPatterns(
            in: multiCategoryCode,
            filePath: "/MultiCategory.swift",
            categories: multipleCategories
        )
        
        print("📊 Multiple Category Filtering:")
        print("   Input: View with state, performance, and accessibility concerns")
        print("   Categories: \(multipleCategories)")
        print("   Issues found: \(issues.count)")
        
        let issuesByCategory = Dictionary(grouping: issues) { issue in
            // Determine category based on rule name
            switch issue.ruleName {
            case .relatedDuplicateStateVariable, .unrelatedDuplicateStateVariable, .unusedStateVariable:
                return PatternCategory.stateManagement
            case .missingAccessibilityLabel:
                return PatternCategory.accessibility
            default:
                return PatternCategory.performance
            }
        }
        
        for (category, categoryIssues) in issuesByCategory {
            print("     \(category): \(categoryIssues.count) issues")
        }
        
    }
    }
