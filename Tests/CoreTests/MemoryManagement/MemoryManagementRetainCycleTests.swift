import Testing
import Foundation
import SwiftSyntax
import SwiftParser
@testable import Core

struct MemoryManagementRetainCycleTests {
    var visitor: MemoryManagementVisitor { MemoryManagementVisitor() }

    @Test func testDetectsPotentialRetainCycle() throws {
        let sourceCode = """
        struct ContentView: View {
            @StateObject var viewModel: ContentViewModel = ContentViewModel()
            var body: some View { Text("Hello") }
        }
        """
        let sourceFile = Parser.parse(source: sourceCode)
        let visitor = self.visitor
        visitor.walk(sourceFile)
        #expect(visitor.detectedIssues.count == 1)
        let issue = try #require(visitor.detectedIssues.first)
        #expect(issue.severity == .warning)
        #expect(issue.message.contains("Potential retain cycle with 'viewModel'"))
        #expect(issue.suggestion?.contains("Review object lifecycle") == true)
    }

    // swiftprojectlint:disable Test Missing Require
    @Test func testDoesNotDetectRetainCycleWhenTypesDiffer() throws {
        let sourceCode = """
        struct ContentView: View {
            @StateObject var viewModel: ContentViewModel = DifferentViewModel()
            var body: some View { Text("Hello") }
        }
        """
        let sourceFile = Parser.parse(source: sourceCode)
        let visitor = self.visitor
        visitor.walk(sourceFile)
        #expect(visitor.detectedIssues.isEmpty)
    }

    // swiftprojectlint:disable Test Missing Require
    @Test func testDoesNotDetectRetainCycleWithoutStateObject() throws {
        let sourceCode = """
        struct ContentView: View {
            @State var viewModel: ContentViewModel = ContentViewModel()
            var body: some View { Text("Hello") }
        }
        """
        let sourceFile = Parser.parse(source: sourceCode)
        let visitor = self.visitor
        visitor.walk(sourceFile)
        #expect(visitor.detectedIssues.isEmpty)
    }

    // swiftprojectlint:disable Test Missing Require
    @Test func testDoesNotDetectRetainCycleWithoutInitializer() throws {
        let sourceCode = """
        struct ContentView: View {
            @StateObject var viewModel: ContentViewModel
            var body: some View { Text("Hello") }
        }
        """
        let sourceFile = Parser.parse(source: sourceCode)
        let visitor = self.visitor
        visitor.walk(sourceFile)
        #expect(visitor.detectedIssues.isEmpty)
    }

    @Test func testDetectsMultipleRetainCycles() throws {
        let sourceCode = """
        struct ContentView: View {
            @StateObject var viewModel1: ViewModel1 = ViewModel1()
            @StateObject var viewModel2: ViewModel2 = ViewModel2()
            var body: some View { Text("Hello") }
        }
        """
        let sourceFile = Parser.parse(source: sourceCode)
        let visitor = self.visitor
        visitor.walk(sourceFile)
        #expect(visitor.detectedIssues.count == 2)
        let issues = visitor.detectedIssues.sorted { $0.message < $1.message }
        let firstIssue = try #require(issues.first)
        #expect(firstIssue.message.contains("viewModel1"))
        #expect(issues.dropFirst().first?.message.contains("viewModel2") == true)
    }
} 
