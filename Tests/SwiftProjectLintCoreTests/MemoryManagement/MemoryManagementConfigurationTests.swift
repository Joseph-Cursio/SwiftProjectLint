import Testing
import Foundation
import SwiftSyntax
import SwiftParser
@testable import SwiftProjectLintCore

struct MemoryManagementConfigurationTests {
    var visitor: MemoryManagementVisitor { MemoryManagementVisitor() }

    // MARK: - Configuration Tests

    @Test func testCustomConfigurationForRetainCycles() throws {
        let config = MemoryManagementVisitor.Configuration(
            maxArraySize: 100,
            detectRetainCycles: false,
            detectLargeObjects: true
        )
        let customVisitor = MemoryManagementVisitor(config: config)
        
        let sourceCode = """
        struct ContentView: View {
            @StateObject var viewModel: ContentViewModel = ContentViewModel()
            var body: some View { Text("Hello") }
        }
        """
        let sourceFile = Parser.parse(source: sourceCode)
        customVisitor.walk(sourceFile)
        #expect(customVisitor.detectedIssues.isEmpty)
    }

    @Test func testCustomConfigurationForLargeObjects() throws {
        let config = MemoryManagementVisitor.Configuration(
            maxArraySize: 5,
            detectRetainCycles: true,
            detectLargeObjects: true
        )
        let customVisitor = MemoryManagementVisitor(config: config)
        
        let sourceCode = """
        struct ContentView: View {
            @State var items: [String] = ["item1", "item2", "item3", "item4", "item5", "item6"]
            var body: some View { Text("Hello") }
        }
        """
        let sourceFile = Parser.parse(source: sourceCode)
        customVisitor.walk(sourceFile)
        #expect(customVisitor.detectedIssues.count == 1)
        let issue = try #require(customVisitor.detectedIssues.first)
        #expect(issue.message.contains("Large array in @State may cause performance issues"))
    }

    // MARK: - Complex Scenarios

    @Test func testComplexViewWithMultipleIssues() throws {
        let sourceCode = """
        struct ContentView: View {
            @StateObject var viewModel: ContentViewModel = ContentViewModel()
            @State var items: [String] = [
                "item1", "item2", "item3", "item4", "item5",
                "item6", "item7", "item8", "item9", "item10",
                "item11", "item12", "item13", "item14", "item15",
                "item16", "item17", "item18", "item19", "item20",
                "item21", "item22", "item23", "item24", "item25",
                "item26", "item27", "item28", "item29", "item30",
                "item31", "item32", "item33", "item34", "item35",
                "item36", "item37", "item38", "item39", "item40",
                "item41", "item42", "item43", "item44", "item45",
                "item46", "item47", "item48", "item49", "item50",
                "item51", "item52", "item53", "item54", "item55",
                "item56", "item57", "item58", "item59", "item60",
                "item61", "item62", "item63", "item64", "item65",
                "item66", "item67", "item68", "item69", "item70",
                "item71", "item72", "item73", "item74", "item75",
                "item76", "item77", "item78", "item79", "item80",
                "item81", "item82", "item83", "item84", "item85",
                "item86", "item87", "item88", "item89", "item90",
                "item91", "item92", "item93", "item94", "item95",
                "item96", "item97", "item98", "item99", "item100",
                "item101"
            ]
            var body: some View {
                VStack {
                    Text("Hello")
                    ForEach(items, id: \\.self) { item in
                        Text(item)
                    }
                }
            }
        }
        """
        let sourceFile = Parser.parse(source: sourceCode)
        let visitor = self.visitor
        visitor.walk(sourceFile)
        #expect(visitor.detectedIssues.count == 2)
        
        let retainCycleIssues = visitor.detectedIssues.filter { $0.message.contains("retain cycle") }
        let largeObjectIssues = visitor.detectedIssues.filter { $0.message.contains("Large array") }
        
        #expect(retainCycleIssues.count == 1)
        #expect(largeObjectIssues.count == 1)
    }

    @Test func testResetClearsDetectedIssues() throws {
        let sourceCode = """
        struct TestView: View {
            @StateObject var viewModel: TestViewModel = TestViewModel()
            var body: some View {
                Text("Hello")
            }
        }
        """
        let sourceFile = Parser.parse(source: sourceCode)
        let visitor = self.visitor
        visitor.walk(sourceFile)
        #expect(visitor.detectedIssues.count == 1)
        visitor.reset()
        #expect(visitor.detectedIssues.isEmpty)
    }
} 
