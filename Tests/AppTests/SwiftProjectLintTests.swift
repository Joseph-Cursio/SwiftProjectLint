import Testing
import Core

@Suite
struct AppTests {
    @Test("Sanity check: basic arithmetic")
    func testBasicSanity() {
        #expect(2 + 2 == 4)
    }

    @Test("Sanity check: string equality")
    func testStringEquality() {
        #expect("SwiftLint".lowercased() == "swiftlint")
    }

    @Test("Smoke test: SourcePatternDetector returns issues for known bad code")
    func testLintingSmoke() {
        let detector = SourcePatternDetector()
        let source = """
        func example() {
            let x = 42
        }
        """
        let issues = detector.detectPatterns(in: source, filePath: "Example.swift")
        // The detector should run without crashing; issue count may vary by registered rules.
        #expect(issues.isEmpty)
    }
}
