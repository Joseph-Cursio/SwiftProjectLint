import Testing
import Foundation
@testable import Core

struct PatternDetectorTests {

    @Test func testDetectPatternsInSourceCode() throws {
        let detector = SourcePatternDetector()
        let sourceCode = """
        import SwiftUI

        struct ContentView: View {
            @State private var isLoading = false
            @State private var counter = 0

            var body: some View {
                VStack {
                    Text("Hello, World!")
                    Button("Increment") {
                        counter += 1
                    }
                }
            }
        }
        """

        _ = detector.detectPatterns(
            in: sourceCode,
            filePath: "/test/ContentView.swift"
        )
    }

    @Test func testDetectPatternsWithSpecificRules() throws {
        let detector = SourcePatternDetector()
        let sourceCode = """
        import SwiftUI

        struct TestView: View {
            @State private var isLoading = false

            var body: some View {
                Text("Test")
            }
        }
        """

        _ = detector.detectPatterns(
            in: sourceCode,
            filePath: "/test/TestView.swift",
            ruleIdentifiers: [.relatedDuplicateStateVariable, .missingStateObject]
        )
    }

    @Test func testDetectPatternsInProject() async throws {
        let detector = CrossFileAnalysisEngine()
        let tempDir = FileManager.default.temporaryDirectory
        let testProjectPath = tempDir.appendingPathComponent("TestProject")

        _ = await detector.detectPatterns(
            in: testProjectPath.path,
            ruleIdentifiers: [.relatedDuplicateStateVariable]
        )
    }

    @Test func testCrossFilePatternDetection() throws {
        let detector = CrossFileAnalysisEngine()

        let projectFiles = [
            ProjectFile(name: "View1.swift", content: """
                struct View1: View {
                    @State private var isLoading = false
                    var body: some View { Text("View1") }
                }
                """),
            ProjectFile(name: "View2.swift", content: """
                struct View2: View {
                    @State private var isLoading = false
                    var body: some View { Text("View2") }
                }
                """)
        ]

        _ = detector.detectCrossFilePatterns(
            projectFiles: projectFiles,
            ruleIdentifiers: [.relatedDuplicateStateVariable]
        )
    }

    @Test func testEmptySourceCode() throws {
        let detector = SourcePatternDetector()
        _ = detector.detectPatterns(in: "", filePath: "/test/Empty.swift")
    }

    @Test func testInvalidSwiftCode() throws {
        let detector = SourcePatternDetector()
        _ = detector.detectPatterns(
            in: "This is not valid Swift code {",
            filePath: "/test/Invalid.swift"
        )
    }
}
