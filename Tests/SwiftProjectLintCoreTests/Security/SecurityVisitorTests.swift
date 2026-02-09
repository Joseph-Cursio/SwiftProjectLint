import Testing
import Foundation
import SwiftParser
import SwiftSyntax
@testable import SwiftProjectLintCore

struct SecurityVisitorTests {
    
    @Test func testHardcodedSecretDetection() throws {
        let sourceCode = """
        let apiKey = "12345"
        let secret = "topsecret"
        let password = "hunter2"
        let token = "abcdef"
        let notASecret = 42
        """
        let sourceFile = Parser.parse(source: sourceCode)
        let visitor = SecurityVisitor(patternCategory: .security)
        visitor.setFilePath("TestFile.swift")
        visitor.walk(sourceFile)
        let issues = visitor.detectedIssues
        
        #expect(issues.count == 4)
        #expect(issues.allSatisfy { $0.severity == .error })
        #expect(issues.allSatisfy { $0.suggestion?.contains("secure key storage") ?? false })
    }
    
    @Test func testUnsafeURLConstruction() throws {
        let sourceCode = """
        let token = "abc123"
        let userId = "user456"
        let unsafeURL1 = URL(string: "https://example.com/api?token=\\(token)")
        let unsafeURL2 = URL(string: "https://example.com/api?user=\\(userId)")
        let safeURL = URL(string: "https://example.com/api")
        """
        let sourceFile = Parser.parse(source: sourceCode)
        let visitor = SecurityVisitor(patternCategory: .security)
        visitor.setFilePath("TestFile.swift")
        visitor.walk(sourceFile)
        let issues = visitor.detectedIssues
        
        #expect(issues.count == 3)
        
        let urlIssues = issues.filter {
            $0.message.localizedCaseInsensitiveContains("string interpolation") && $0.severity == .warning
        }
        #expect(urlIssues.count == 2)
        
        let secretIssues = issues.filter {
            $0.message.localizedCaseInsensitiveContains("hardcoded") && $0.severity == .error
        }
        #expect(secretIssues.count == 1)
    }
} 
