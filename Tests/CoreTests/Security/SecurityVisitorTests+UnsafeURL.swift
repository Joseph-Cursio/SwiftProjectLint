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

    /// The constant is judged by the strings its own `+` joins, not by the rest of the argument:
    /// a `??` fallback before it does not make it a computed string.
    @Test func testConcatenatedConstantsBehindAFallbackAreNotUnsafe() {
        let source = """
        let fallback = URL(string: configured ?? "https://example.com/" + "v2")
        let chosen = URL(string: flag ? "https://example.com/" + "v1" : "https://example.com/" + "v2")
        """
        #expect(unsafeURLIssues(source).isEmpty)
    }

    /// **Arithmetic is not concatenation.** A `+` inside a subscript, a call or another argument
    /// is not one of the `string:` argument's own operators.
    @Test func testArithmeticIsNotConcatenation() {
        let source = """
        let page = URL(string: pages[index + 1])
        let built = URL(string: path(for: page + 1))
        let relative = URL(string: "https://example.com/", relativeTo: bases[offset + 1])
        let chosen = URL(string: index + 1 < count ? next : last)
        """
        #expect(unsafeURLIssues(source).isEmpty)
    }

    /// **A ternary's condition is never the URL's text**, whatever its branches hold. A string
    /// literal in a branch, or in the comparison itself, used to count as evidence that the
    /// condition's `+` joined strings — but only the branches become the URL.
    @Test func testArithmeticInATernaryConditionIsNotConcatenation() {
        let source = """
        let backup = URL(string: retries + 1 < maxRetries ? primaryURL : "https://backup.example.com")
        let end = URL(string: index + 1 < count ? pages[index + 1] : "https://example.com/end")
        let constant = URL(string: page + 1 == 1 ? "https://example.com/first" : "https://example.com/rest")
        let compared = URL(string: env + suffix == "prod" ? prodURL : stagingURL)
        let nested = URL(string: offset + 1 == total ? base : fallback ?? "https://example.com")
        let parenthesised = URL(string: (index + 1) < count ? next : "about:blank")
        """
        #expect(unsafeURLIssues(source).isEmpty)
    }

    /// **The text is read wherever it becomes the URL**: either side of a `??`, either branch of
    /// a `?:`, and inside parentheses at each of them. `??` binds looser than `+`, so in
    /// `configured ?? base + path` the fallback is the concatenation — no literal needed.
    @Test func testConcatenationUnderFallbackOrTernaryIsUnsafe() {
        let source = """
        let fallback = URL(string: configured ?? "https://example.com/" + path)
        let bare = URL(string: configured ?? base + path)
        let wrapped = URL(string: configured ?? ("https://example.com/" + path))
        let otherwise = URL(string: flag ? fallback : "https://example.com/" + path)
        let then = URL(string: flag ? "https://example.com/" + path : fallback)
        let grouped = URL(string: flag ? fallback : ("https://example.com/" + path))
        let cast = URL(string: value as? String ?? base + path)
        """
        let issues = unsafeURLIssues(source)
        #expect(issues.map(\.lineNumber) == [1, 2, 3, 4, 5, 6, 7])
        #expect(issues.allSatisfy { $0.message == "Unsafe URL construction with string concatenation" })
    }

    /// An interpolated literal is reported in the same places a concatenation is, with its own
    /// message.
    @Test func testInterpolationUnderFallbackOrTernaryIsUnsafe() {
        let source = """
        let fallback = URL(string: configured ?? "https://example.com/\\(path)")
        let chosen = URL(string: flag ? "https://example.com/\\(path)" : fallback)
        let otherwise = URL(string: flag ? fallback : ("https://example.com/\\(path)"))
        """
        let issues = unsafeURLIssues(source)
        #expect(issues.map(\.lineNumber) == [1, 2, 3])
        #expect(issues.allSatisfy { $0.message == "Unsafe URL construction with string interpolation" })
    }

    /// A fallback, a choice or a cast with no `+` and no interpolation joins nothing.
    @Test func testFallbackAndChoiceWithoutJoiningAreNotUnsafe() {
        let source = """
        let fallback = URL(string: configured ?? "https://example.com/")
        let chosen = URL(string: flag ? primaryURL : "https://example.com/")
        let cast = URL(string: value as? String ?? "https://example.com/")
        """
        #expect(unsafeURLIssues(source).isEmpty)
    }
}
