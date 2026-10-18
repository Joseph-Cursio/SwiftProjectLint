@testable import Core
import Testing

/// Unsafe URL's reading of the `string:` argument: which parts of it are the URL's text, and when
/// a `+` there is a concatenation rather than a character of a constant or arithmetic.
extension SecurityVisitorTests {

    // MARK: - Unsafe URL: a `+` is an operator, not a character

    /// **A `+` inside a constant is part of the URL.** The rule used to search the literal's
    /// source text for `+` and `\(`, so an international phone number and a form-encoded space
    /// were reported as "string interpolation" — and so was a raw string, whose `\(` is two
    /// characters of text, not an interpolation.
    @Test func testPlusInsideAConstantURLIsNotUnsafe() {
        let source = """
        let phone = URL(string: "tel:+15551234567")
        let search = URL(string: "https://example.com/search?q=swift+ui")
        let raw = URL(string: #"https://example.com/\\(literally)"#)
        """
        #expect(unsafeURLIssues(source).isEmpty)
    }

    /// **Concatenation is a sequence expression, not a literal**, so it was never examined: the
    /// `+` search ran only when the argument was a string literal. A chain of `+` is the
    /// `String` that `URL(string:)` takes, so `base + path` is reported without a literal in it.
    @Test func testConcatenationIsUnsafe() {
        let source = """
        let joined = URL(string: base + path)
        let query = URL(string: "https://example.com/api?q=" + query)
        let several = URL(string: base + "/users/" + userID + "?expand=" + fields)
        """
        let issues = unsafeURLIssues(source)
        #expect(issues.map(\.lineNumber) == [1, 2, 3])
        #expect(issues.allSatisfy { $0.message == "Unsafe URL construction with string concatenation" })
        #expect(issues.allSatisfy { $0.severity == .warning })
    }

    /// The parser leaves a parenthesised operand as a tuple holding its own sequence, and an
    /// interpolated literal inside a chain still makes the chain a concatenation.
    @Test func testParenthesisedConcatenationIsUnsafe() {
        let source = """
        let nested = URL(string: base + ("/" + path))
        let wrapped = URL(string: ("https://example.com/" + path))
        let grouped = URL(string: (scheme + host) + path)
        let segment = URL(string: "https://example.com/" + "\\(path)")
        """
        let issues = unsafeURLIssues(source)
        #expect(issues.map(\.lineNumber) == [1, 2, 3, 4])
        #expect(issues.allSatisfy { $0.message.hasSuffix("string concatenation") })
    }

    /// Each finding names what it found: an interpolated literal is not called a concatenation,
    /// and parentheses around one change nothing.
    @Test func testInterpolationKeepsItsOwnMessage() {
        let source = """
        let interpolated = URL(string: ("https://example.com/\\(path)"))
        """
        let issues = unsafeURLIssues(source)
        #expect(issues.count == 1)
        #expect(issues.first?.message == "Unsafe URL construction with string interpolation")
    }

    /// Literals joined with `+` are one constant split across lines — nothing in them is computed
    /// at run time, so there is nothing to encode.
    @Test func testConcatenatedConstantsAreNotUnsafe() {
        let source = """
        let long = URL(string: "https://example.com/" + "v2/users")
        let split = URL(string: "https://example.com/"
            + "v2/"
            + ("users?page=1"))
        """
        #expect(unsafeURLIssues(source).isEmpty)
    }

    /// **Arithmetic is not concatenation.** A `+` inside a subscript, a call or another argument
    /// is not one of the `string:` argument's own operators, and a `+` mixed with other operators
    /// is concatenation only when a string literal is among its operands — in a ternary's
    /// condition it is arithmetic.
    @Test func testArithmeticIsNotConcatenation() {
        let source = """
        let page = URL(string: pages[index + 1])
        let built = URL(string: path(for: page + 1))
        let relative = URL(string: "https://example.com/", relativeTo: bases[offset + 1])
        let chosen = URL(string: index + 1 < count ? next : last)
        """
        #expect(unsafeURLIssues(source).isEmpty)
    }

    /// A mixed expression whose operands include a string literal is text being joined, whatever
    /// else it does: `??` binds looser than `+`, so the fallback is the concatenation.
    @Test func testMixedOperatorsWithALiteralAreConcatenation() {
        let source = """
        let fallback = URL(string: configured ?? "https://example.com/" + path)
        """
        let issues = unsafeURLIssues(source)
        #expect(issues.count == 1)
        #expect(issues.first?.message == "Unsafe URL construction with string concatenation")
    }
}
