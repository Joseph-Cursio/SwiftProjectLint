import Testing
import Foundation
@testable import SwiftProjectLintCore

struct DebugLoggerTests {
    
    @Test @MainActor func testIsEnabledFlag() throws {
        #if DEBUG
        #expect(DebugLogger.isEnabled)
        #else
        #expect(DebugLogger.isEnabled == false)
        #endif
    }
    
    #if DEBUG
    @Test @MainActor func testDebugDirectoryCreatesAndReturnsPath() throws {
        let debugDir = DebugLogger.debugDirectory()
        #expect(debugDir.hasSuffix("/debug_output"))
        #expect(FileManager.default.fileExists(atPath: debugDir, isDirectory: nil))
    }
    
    @Test @MainActor func testLogPrintsMessage() throws {
        var logs: [String] = []
        let originalOutputHandler = DebugLogger.outputHandler
        DebugLogger.outputHandler = { logs.append($0) }
        defer { DebugLogger.outputHandler = originalOutputHandler }
        
        DebugLogger.log("Test message", file: "/tmp/TestFile.swift", function: "testFunc", line: 42)
        
        let output = logs.joined(separator: "\n")
        #expect(output.contains("DEBUG [TestFile.swift:42] testFunc: Test message"))
    }
    
    @Test @MainActor func testLogASTPrintsAST() throws {
        var logs: [String] = []
        let originalOutputHandler = DebugLogger.outputHandler
        DebugLogger.outputHandler = { logs.append($0) }
        defer { DebugLogger.outputHandler = originalOutputHandler }
        
        DebugLogger.logAST("AST_STRING", file: "/tmp/ASTFile.swift", function: "astFunc", line: 99)
        
        let output = logs.joined(separator: "\n")
        #expect(output.contains("ASTFile.swift:99"))
        #expect(output.contains("astFunc"))
        #expect(output.contains("AST Structure:"))
        #expect(output.contains("AST_STRING"))
    }
    
    @Test @MainActor func testLogVisitorPrintsVisitorMessage() throws {
        var logs: [String] = []
        let originalOutputHandler = DebugLogger.outputHandler
        DebugLogger.outputHandler = { logs.append($0) }
        defer { DebugLogger.outputHandler = originalOutputHandler }
        
        DebugLogger.logVisitor(
            .performance, "Visitor message",
            file: "/tmp/VisitorFile.swift", function: "visitorFunc", line: 77
        )
        
        let output = logs.joined(separator: "\n")
        #expect(output.contains("VisitorFile.swift:77"))
        #expect(output.contains("PerformanceVisitor.visitorFunc"))
        #expect(output.contains("Visitor message"))
    }
    
    @Test @MainActor func testLogIssuePrintsIssue() throws {
        var logs: [String] = []
        let originalOutputHandler = DebugLogger.outputHandler
        DebugLogger.outputHandler = { logs.append($0) }
        defer { DebugLogger.outputHandler = originalOutputHandler }
        
        DebugLogger.logIssue("ISSUE!", file: "/tmp/IssueFile.swift", function: "issueFunc", line: 55)
        
        let output = logs.joined(separator: "\n")
        #expect(output.contains("IssueFile.swift:55"))
        #expect(output.contains("issueFunc"))
        #expect(output.contains("ISSUE DETECTED: ISSUE!"))
    }
    
    @Test @MainActor func testLogNodePrintsNode() throws {
        var logs: [String] = []
        let originalOutputHandler = DebugLogger.outputHandler
        DebugLogger.outputHandler = { logs.append($0) }
        defer { DebugLogger.outputHandler = originalOutputHandler }
        
        DebugLogger.logNode("IfExpr", "details here", file: "/tmp/NodeFile.swift", function: "nodeFunc", line: 12)
        
        let output = logs.joined(separator: "\n")
        #expect(output.contains("NodeFile.swift:12"))
        #expect(output.contains("nodeFunc"))
        #expect(output.contains("Visiting IfExpr - details here"))
    }
    #else
    @Test func testReleaseLoggerDoesNothing() throws {
        // All log methods should be no-ops and not crash
        DebugLogger.log("msg")
        DebugLogger.logAST("ast")
        DebugLogger.logVisitor(.performance, "msg")
        DebugLogger.logIssue("issue")
        DebugLogger.logNode("node", "details")
        #expect(DebugLogger.isEnabled == false)
    }
    #endif
}
