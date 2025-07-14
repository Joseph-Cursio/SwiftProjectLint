import Testing
import Foundation
@testable import SwiftProjectLintCore

final class AdvancedAnalyzerTests {
    
    @Test func testExtractViewNameRemovesSwiftExtension() async throws {
        let analyzer = AdvancedAnalyzer()
        let name = analyzer.extractViewName(from: "/Users/test/ContentView.swift")
        #expect(name == "ContentView")
        
        let name2 = analyzer.extractViewName(from: "MyView.swift")
        #expect(name2 == "MyView")
        
        let name3 = analyzer.extractViewName(from: "/foo/bar/BazView.swift")
        #expect(name3 == "BazView")
    }
    
    @Test func testFindDuplicatesReturnsCorrectDuplicates() async throws {
        let analyzer = AdvancedAnalyzer()
        let input = ["a", "b", "c", "a", "d", "b"]
        let result = analyzer.findDuplicates(in: input)
        
        #expect(result.contains("a"))
        #expect(result.contains("b"))
        #expect(!result.contains("c"))
        #expect(!result.contains("d"))
    }
    
    @Test func testFindRelatedViewsDetectsHierarchy() async throws {
        let analyzer = AdvancedAnalyzer()
        analyzer.viewHierarchies = ["Parent": ["Child1", "Child2"], "Child1": ["Grandchild"]]
        
        let related = analyzer.findRelatedViews(["Parent", "Child1"])
        #expect(related.contains("Child1"))
        #expect(related.contains("Child2"))
        #expect(related.contains("Grandchild"))
    }
    
    @Test func testIsRootViewReturnsTrueForRoot() async throws {
        let analyzer = AdvancedAnalyzer()
        analyzer.viewHierarchies = ["Root": ["Child"], "Child": ["Grandchild"]]
        
        #expect(analyzer.isRootView("Root"))
        #expect(!analyzer.isRootView("Child"))
        #expect(!analyzer.isRootView("Grandchild"))
    }
    
    @Test func testGenerateStateSharingSuggestionForTwoViews() async throws {
        let analyzer = AdvancedAnalyzer()
        let suggestion = analyzer.generateStateSharingSuggestion(for: "userSettings", views: ["RootView", "DetailsView"])
        
        #expect(suggestion.contains("pass it from RootView to DetailsView"))
    }
    
    @Test func testGenerateStateSharingSuggestionForManyViews() async throws {
        let analyzer = AdvancedAnalyzer()
        let suggestion = analyzer.generateStateSharingSuggestion(for: "userSettings", views: ["A", "B", "C"])
        
        #expect(suggestion.contains(".environmentObject()"))
        #expect(suggestion.contains("3 views"))
    }
    
    @Test func testRelationshipTypeAndViewRelationship() async throws {
        let analyzer = AdvancedAnalyzer()
        let rel = ViewRelationship(
            parentView: "A",
            childView: "B",
            relationshipType: .navigationDestination,
            lineNumber: 10,
            filePath: "/tmp/A.swift"
        )
        analyzer.viewRelationships = [rel]
        
        #expect(analyzer.relationshipType(between: "A", and: "B") == .navigationDestination)
        
        let found = analyzer.viewRelationship(between: "A", and: "B")
        #expect(found != nil)
        #expect(found?.parentView == "A")
        #expect(found?.childView == "B")
    }
}
