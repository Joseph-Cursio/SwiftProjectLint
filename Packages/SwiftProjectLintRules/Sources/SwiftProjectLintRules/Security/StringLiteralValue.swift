import SwiftParser
import SwiftSyntax

/// The **value** of a string literal, as opposed to its source text.
///
/// Extracted because three security visitors each had a `extractStringValue` and they did not
/// agree. `SecurityVisitor` read `literal.segments` — the route SwiftSyntax provides, which hands
/// back the decoded content. `InsecureTransportVisitor` and `UserDefaultsSensitiveDataVisitor`
/// sliced `literal.description` with `dropFirst().dropLast()`, which operates on **source text**:
///
/// - `"a\"b"` is seven characters of source. Stripping the outer quotes yields `a\"b` — a string
///   containing a literal backslash, not the value `a"b`. Any downstream comparison against a real
///   string then silently fails to match.
/// - A multiline literal `"""abc"""` starts and ends with `"` and is longer than two characters, so
///   it passes the guard and yields `""abc""` — two stray quotes on each end.
///
/// Neither visitor is *reported* wrong by these; a URL scheme check simply stops recognising the
/// value, and a sensitive-key check stops matching. Silent under-detection in a security rule.
///
/// The interpolation guard is kept, and it is the one thing the sliced versions got right that the
/// segment version does not: a literal with `\(...)` in it has no compile-time value, and joining
/// only its literal segments would invent one.
enum StringLiteralValue {

    /// The literal's value, or `nil` when it has no compile-time value.
    ///
    /// `nil` for an interpolated literal — `"\(scheme)://x"` is not a constant, and returning
    /// `"://x"` would hand a caller a value the program never has.
    /// A property test drove this to the right API. The first cut joined
    /// `StringSegmentSyntax.content.text`, which is still **source text**: the literal `"\\"` came
    /// back as two backslashes rather than the one character it denotes. Better than slicing
    /// `description`, and wrong in the same direction.
    ///
    /// `representedLiteralValue` is SwiftSyntax's own decoder. It handles escapes, multiline
    /// literals and raw (`#"..."#`) delimiters, and returns `nil` for an interpolated literal —
    /// which is exactly the refusal this needs, for free.
    static func of(_ literal: StringLiteralExprSyntax) -> String? {
        literal.representedLiteralValue
    }
}
