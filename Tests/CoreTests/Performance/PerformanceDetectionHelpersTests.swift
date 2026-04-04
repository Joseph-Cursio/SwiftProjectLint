import Testing
import SwiftParser
import SwiftSyntax
@testable import Core
@testable import SwiftProjectLintRules

@Suite("ForEach ID detection via PerformanceVisitor")
struct PerformanceDetectionHelpersTests {

    private func makeVisitor(source: String) -> PerformanceVisitor {
        let syntax = Parser.parse(source: source)
        let visitor = PerformanceVisitor(patternCategory: .performance)
        visitor.setFilePath("test.swift")
        visitor.walk(syntax)
        return visitor
    }

    @Test("Detects ForEach with backslash-self ID")
    func detectsBackslashSelf() throws {
        let source = """
        struct ContentView: View {
            var items = [1, 2, 3]
            var body: some View {
                ForEach(items, id: \\.self) { item in
                    Text("\\(item)")
                }
            }
        }
        """

        let visitor = makeVisitor(source: source)
        let forEachSelfIssues = visitor.detectedIssues.filter {
            $0.message.contains("ForEach") && $0.message.contains("self")
        }

        let issue = try #require(forEachSelfIssues.first)
        #expect(issue.severity == .warning)
        #expect(issue.message.contains("\\.self"))
    }

    @Test("Does not flag .self via MemberAccessExpr (no backslash)")
    func doesNotFlagMemberAccessSelf() throws {
        let source = """
        struct ContentView: View {
            var items = [1, 2, 3]
            var body: some View {
                ForEach(items, id: .self) { item in
                    Text("\\(item)")
                }
            }
        }
        """

        let visitor = makeVisitor(source: source)
        let forEachSelfIssues = visitor.detectedIssues.filter {
            $0.message.contains("ForEach") && $0.message.contains("self")
        }

        #expect(forEachSelfIssues.isEmpty)
    }

    @Test("Does not flag ForEach with proper ID keypath")
    func doesNotFlagProperID() throws {
        let source = """
        struct Item {
            let id: String
        }
        struct ContentView: View {
            var items = [Item(id: "1"), Item(id: "2")]
            var body: some View {
                ForEach(items, id: \\.id) { item in
                    Text(item.id)
                }
            }
        }
        """

        let visitor = makeVisitor(source: source)
        let forEachSelfIssues = visitor.detectedIssues.filter {
            $0.message.contains("self")
        }

        #expect(forEachSelfIssues.isEmpty)
    }

    @Test("Detects ForEach without ID parameter")
    func detectsMissingIDParameter() throws {
        let source = """
        struct ContentView: View {
            var items = [1, 2, 3]
            var body: some View {
                ForEach(items) { item in
                    Text("\\(item)")
                }
            }
        }
        """

        let visitor = makeVisitor(source: source)
        let forEachIssues = visitor.detectedIssues.filter {
            $0.message.contains("ForEach") && $0.message.contains("missing")
        }

        let issue = try #require(forEachIssues.first)
        #expect(issue.severity == .warning)
    }

    @Test("Detects ForEach with explicit keypath self")
    func detectsExplicitKeypathSelf() throws {
        let source = """
        struct ContentView: View {
            var items = ["a", "b", "c"]
            var body: some View {
                ForEach(items, id: \\.self) { item in
                    Text(item)
                }
            }
        }
        """

        let visitor = makeVisitor(source: source)
        let forEachSelfIssues = visitor.detectedIssues.filter {
            $0.message.contains("ForEach") && $0.message.contains("self")
        }

        #expect(forEachSelfIssues.count == 1)
    }

    @Test("Does not flag List with self ID")
    func doesNotFlagNonForEach() throws {
        let source = """
        struct ContentView: View {
            var items = [1, 2, 3]
            var body: some View {
                List(items, id: \\.self) { item in
                    Text("\\(item)")
                }
            }
        }
        """

        let visitor = makeVisitor(source: source)
        let forEachSelfIssues = visitor.detectedIssues.filter {
            $0.message.contains("ForEach") && $0.message.contains("self")
        }

        #expect(forEachSelfIssues.isEmpty)
    }

    @Test("Detects self ID in nested ForEach")
    func detectsNestedForEach() throws {
        let source = """
        struct ContentView: View {
            var items = [[1, 2], [3, 4]]
            var body: some View {
                ForEach(items, id: \\.self) { row in
                    ForEach(row, id: \\.self) { item in
                        Text("\\(item)")
                    }
                }
            }
        }
        """

        let visitor = makeVisitor(source: source)
        let forEachSelfIssues = visitor.detectedIssues.filter {
            $0.message.contains("ForEach") && $0.message.contains("self")
        }

        #expect(forEachSelfIssues.count == 2)
    }

    @Test("Detects self ID with complex collection expression")
    func detectsComplexExpression() throws {
        let source = """
        struct ContentView: View {
            var items = [1, 2, 3]
            var body: some View {
                VStack {
                    ForEach(items.sorted(), id: \\.self) { item in
                        Text("\\(item)")
                    }
                }
            }
        }
        """

        let visitor = makeVisitor(source: source)
        let forEachSelfIssues = visitor.detectedIssues.filter {
            $0.message.contains("ForEach") && $0.message.contains("self")
        }

        #expect(forEachSelfIssues.count == 1)
    }

    @Test("Flags hashValue as unsafe ID keypath")
    func detectsHashValueID() throws {
        let source = """
        struct ContentView: View {
            var items = [Item(name: "a"), Item(name: "b")]
            var body: some View {
                ForEach(items, id: \\.hashValue) { item in
                    Text(item.name)
                }
            }
        }
        """

        let visitor = makeVisitor(source: source)
        let hashValueIssues = visitor.detectedIssues.filter {
            $0.message.contains("hashValue")
        }

        let issue = try #require(hashValueIssues.first)
        #expect(issue.severity == .warning)
    }

    @Test("Does not flag hashValue for proper ID keypath")
    func doesNotFlagProperIDForHashValue() throws {
        let source = """
        struct ContentView: View {
            var items = [Item(id: "1"), Item(id: "2")]
            var body: some View {
                ForEach(items, id: \\.id) { item in
                    Text(item.id)
                }
            }
        }
        """

        let visitor = makeVisitor(source: source)
        let hashValueIssues = visitor.detectedIssues.filter {
            $0.message.contains("hashValue")
        }

        #expect(hashValueIssues.isEmpty)
    }

    @Test("Detects missing ID in empty array ForEach")
    func detectsMissingIDEdgeCase() throws {
        let source = """
        struct ContentView: View {
            var body: some View {
                ForEach([]) { _ in
                    Text("Empty")
                }
            }
        }
        """

        let visitor = makeVisitor(source: source)
        let forEachIssues = visitor.detectedIssues.filter {
            $0.message.contains("ForEach") && $0.message.contains("missing")
        }

        #expect(forEachIssues.count == 1)
    }
}
