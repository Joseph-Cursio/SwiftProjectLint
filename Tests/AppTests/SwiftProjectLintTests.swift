import Testing

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

    @Test("Placeholder for linting logic")
    func testExampleLinting() {
        // TODO: Replace with actual linting call if public API is available
        #expect(true, "Replace this with a real linting test.")
    }
}
