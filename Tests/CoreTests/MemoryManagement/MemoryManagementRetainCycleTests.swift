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
        #expect(issues[0].message.contains("viewModel1"))
        #expect(issues[1].message.contains("viewModel2"))
    }
} 
