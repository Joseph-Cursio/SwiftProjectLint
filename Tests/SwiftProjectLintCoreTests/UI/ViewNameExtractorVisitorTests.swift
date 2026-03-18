import Testing
import SwiftParser
import SwiftSyntax
@testable import SwiftProjectLintCore

@Suite("ViewNameExtractorVisitorTests")
struct ViewNameExtractorVisitorTests {
    
    @Test func testExtractsViewNames() throws {
        let source = """
        struct ContentView: View {
            var body: some View {
                Text("Hello")
            }
        }
        
        struct SettingsView: View {
            var body: some View {
                Text("Settings")
            }
        }
        """
        
        let syntax = Parser.parse(source: source)
        let visitor = ViewNameExtractorVisitor(viewMode: .sourceAccurate)
        visitor.walk(syntax)
        
        #expect(visitor.viewNames.count == 2)
        #expect(visitor.viewNames.contains("ContentView"))
        #expect(visitor.viewNames.contains("SettingsView"))
    }
    
    @Test func testIgnoresNonViewStructs() throws {
        let source = """
        struct DataModel {
            let name: String
        }
        
        struct ContentView: View {
            var body: some View {
                Text("Hello")
            }
        }
        
        struct Helper {
            func doSomething() {}
        }
        """
        
        let syntax = Parser.parse(source: source)
        let visitor = ViewNameExtractorVisitor(viewMode: .sourceAccurate)
        visitor.walk(syntax)
        
        #expect(visitor.viewNames.count == 1)
        #expect(visitor.viewNames.contains("ContentView"))
        #expect(!visitor.viewNames.contains("DataModel"))
        #expect(!visitor.viewNames.contains("Helper"))
    }
    
    @Test func testHandlesEmptySource() throws {
        let source = ""
        let syntax = Parser.parse(source: source)
        let visitor = ViewNameExtractorVisitor(viewMode: .sourceAccurate)
        visitor.walk(syntax)
        
        #expect(visitor.viewNames.isEmpty)
    }
    
    @Test func testHandlesMultipleViews() throws {
        let source = """
        struct View1: View {
            var body: some View { Text("1") }
        }
        struct View2: View {
            var body: some View { Text("2") }
        }
        struct View3: View {
            var body: some View { Text("3") }
        }
        """
        
        let syntax = Parser.parse(source: source)
        let visitor = ViewNameExtractorVisitor(viewMode: .sourceAccurate)
        visitor.walk(syntax)
        
        #expect(visitor.viewNames.count == 3)
        #expect(visitor.viewNames.contains("View1"))
        #expect(visitor.viewNames.contains("View2"))
        #expect(visitor.viewNames.contains("View3"))
    }
    
    @Test func testHandlesViewsWithProtocolConformance() throws {
        let source = """
        struct MyView: View, Equatable {
            var body: some View {
                Text("Hello")
            }
        }
        """
        
        let syntax = Parser.parse(source: source)
        let visitor = ViewNameExtractorVisitor(viewMode: .sourceAccurate)
        visitor.walk(syntax)
        
        #expect(visitor.viewNames.count == 1)
        #expect(visitor.viewNames.contains("MyView"))
    }
}
