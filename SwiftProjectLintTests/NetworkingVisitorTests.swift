import Testing
import Foundation
import SwiftSyntax
import SwiftParser
@testable import SwiftProjectLintCore

struct NetworkingVisitorTests {
    
    @Test func testVisitorInitialization() async throws {
        let visitor = NetworkingVisitor(patternCategory: .networking)
        
        #expect(visitor != nil)
        #expect(visitor.patternCategory == .networking)
        #expect(visitor.detectedIssues.count == 0)
    }
    
    @Test func testManualIssueCreation() async throws {
        let visitor = NetworkingVisitor(patternCategory: .networking)
        let issue = LintIssue(
            severity: .error,
            message: "Test issue",
            filePath: "test.swift",
            lineNumber: 1,
            suggestion: "Test suggestion",
            ruleName: "Test Rule"
        )
        visitor.detectedIssues.append(issue)
        
        #expect(visitor.detectedIssues.count == 1)
        #expect(visitor.detectedIssues.first?.message == "Test issue")
    }
    
    @Test func testDetectsSynchronousNetworking() async throws {
        let visitor = NetworkingVisitor(patternCategory: .networking)
        let source = """
        let url = URL(string: "https://example.com")!
        let data = try Data(contentsOf: url)
        """
        print("🔍 Testing source code:")
        print(source)
        print("---")
        
        let syntax = Parser.parse(source: source)
        print("🔍 Parsed syntax tree:")
        print(syntax.description)
        print("---")
        
        // Set up source location converter
        let converter = SourceLocationConverter(fileName: "test.swift", tree: syntax)
        visitor.setSourceLocationConverter(converter)
        
        visitor.walk(syntax)
        let issues = visitor.detectedIssues
        
        print("🔍 Detected issues: \(issues.count)")
        for (index, issue) in issues.enumerated() {
            print("  Issue \(index + 1):")
            print("    Message: '\(issue.message)'")
            print("    Severity: \(issue.severity)")
            print("    Line: \(issue.lineNumber)")
            print("    Suggestion: '\(issue.suggestion ?? "nil")'")
        }
        print("---")
        
        #expect(issues.count == 1, "Expected 1 issue, but got \(issues.count)")
        if let firstIssue = issues.first {
            #expect(firstIssue.message == "Synchronous networking can block the UI thread", "Expected message 'Synchronous networking can block the UI thread', but got '\(firstIssue.message)'")
            #expect(firstIssue.severity == .error, "Expected severity .error, but got \(firstIssue.severity)")
        } else {
            #expect(false, "No issues detected")
        }
    }
    
    @Test func testDetectsMissingErrorHandlingInDataTask() async throws {
        let visitor = NetworkingVisitor(patternCategory: .networking)
        let source = """
        let url = URL(string: "https://example.com")!
        URLSession.shared.dataTask(with: url) { data, response, _ in
            // No error handling
        }.resume()
        """
        print("🔍 Testing source code:")
        print(source)
        print("---")
        
        let syntax = Parser.parse(source: source)
        print("🔍 Parsed syntax tree:")
        print(syntax.description)
        print("---")
        
        // Set up source location converter
        let converter = SourceLocationConverter(fileName: "test.swift", tree: syntax)
        visitor.setSourceLocationConverter(converter)
        
        visitor.walk(syntax)
        let issues = visitor.detectedIssues
        
        print("🔍 Detected issues: \(issues.count)")
        for (index, issue) in issues.enumerated() {
            print("  Issue \(index + 1):")
            print("    Message: '\(issue.message)'")
            print("    Severity: \(issue.severity)")
            print("    Line: \(issue.lineNumber)")
            print("    Suggestion: '\(issue.suggestion ?? "nil")'")
        }
        print("---")
        
        #expect(issues.count == 1, "Expected 1 issue, but got \(issues.count)")
        if let firstIssue = issues.first {
            #expect(firstIssue.message == "Network request missing error handling", "Expected message 'Network request missing error handling', but got '\(firstIssue.message)'")
            #expect(firstIssue.severity == .warning, "Expected severity .warning, but got \(firstIssue.severity)")
        } else {
            #expect(false, "No issues detected")
        }
    }
    
    @Test func testDoesNotDetectWhenErrorHandled() async throws {
        let visitor = NetworkingVisitor(patternCategory: .networking)
        let source = """
        let url = URL(string: "https://example.com")!
        URLSession.shared.dataTask(with: url) { data, response, error in
            if let error = error {
                print(error)
            }
        }.resume()
        """
        let syntax = Parser.parse(source: source)
        visitor.walk(syntax)
        let issues = visitor.detectedIssues
        
        #expect(issues.count == 0)
    }
} 