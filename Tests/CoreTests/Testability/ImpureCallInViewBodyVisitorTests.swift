@testable import Core
import SwiftParser
@testable import SwiftProjectLintRules
import SwiftSyntax
import Testing

@Suite
struct ImpureCallInViewBodyVisitorTests {

    private func analyze(_ source: String) -> [LintIssue] {
        let visitor = ImpureCallInViewBodyVisitor(patternCategory: .testability)
        let syntax = Parser.parse(source: source)
        visitor.setSourceLocationConverter(SourceLocationConverter(fileName: "View.swift", tree: syntax))
        visitor.setFilePath("View.swift")
        visitor.walk(syntax)
        return visitor.detectedIssues.filter { $0.ruleName == .impureCallInViewBody }
    }

    @Test
    func flagsUserDefaultsReadInBody() {
        let issues = analyze("""
        struct ContentView: View {
            var body: some View {
                Text("\\(UserDefaults.standard.integer(forKey: "count"))")
            }
        }
        """)
        #expect(issues.count == 1)
        #expect(issues.first?.message.contains("UserDefaults") == true)
    }

    @Test
    func flagsPrintInBody() {
        let issues = analyze("""
        struct ContentView: View {
            var body: some View {
                print("rendering")
                Text("x")
            }
        }
        """)
        #expect(issues.count == 1)
        #expect(issues.first?.message.contains("print") == true)
    }

    @Test
    func flagsFileManagerAndURLSession() {
        let issues = analyze("""
        struct ContentView: View {
            var body: some View {
                let exists = FileManager.default.fileExists(atPath: "/tmp/x")
                let task = URLSession.shared.dataTask(with: url)
                Text("\\(exists)")
            }
        }
        """)
        #expect(issues.count == 2)
    }

    @Test
    func ignoresImpureCallOutsideBody() {
        // Only `body` is scanned — a helper method using UserDefaults is fine.
        let issues = analyze("""
        struct ContentView: View {
            func persist() {
                UserDefaults.standard.set(1, forKey: "k")
            }
            var body: some View {
                Text("x")
            }
        }
        """)
        #expect(issues.isEmpty)
    }

    @Test
    func ignoresPureBody() {
        let issues = analyze("""
        struct ContentView: View {
            let title: String
            var body: some View {
                VStack {
                    Text(title)
                    Image(systemName: "star")
                }
            }
        }
        """)
        #expect(issues.isEmpty)
    }

    @Test
    func ignoresNonViewStructWithBody() {
        // A non-View struct that happens to have a `body` property is not a SwiftUI view.
        let issues = analyze("""
        struct Response {
            var body: String {
                UserDefaults.standard.string(forKey: "cached") ?? ""
            }
        }
        """)
        #expect(issues.isEmpty)
    }

    @Test
    func flagsEachMarkerOccurrence() {
        let issues = analyze("""
        struct ContentView: View {
            var body: some View {
                let _ = print("a")
                let _ = NSLog("b")
                DispatchQueue.main.async { }
                Text("x")
            }
        }
        """)
        #expect(issues.count == 3)
    }
}
