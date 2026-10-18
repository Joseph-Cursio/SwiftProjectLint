[← Back to Rules](RULES.md)

## Unsafe URL

**Identifier:** `Unsafe URL`
**Category:** Security
**Severity:** Warning

### Rationale
Constructing URLs by splicing in text at run time — string interpolation, `URL(string: "https://example.com/\(path)")`, or concatenation, `URL(string: base + path)` — is unsafe for two reasons: user-controlled input may contain characters that break URL parsing, leading to unexpected behavior; and without percent-encoding, the resulting URL may be malformed or bypass server-side validation.

### Discussion
`SecurityVisitor` reads the `string:` argument of a `URL(...)` call off the syntax tree, and reports it when it is either:

- **an interpolated string literal** — a literal with an `\(…)` segment. The message says *string interpolation*.
- **a `+` concatenation** — the parser leaves `base + "/" + path` as one flat sequence of operands and operators, and a parenthesised operand as a nested one. The message says *string concatenation*. A `+` counts as concatenation, not arithmetic, when every operator in the argument is `+` (the chain is then the whole argument, and the argument is the `String` that `URL(string:)` takes — so `base + path` is reported though nothing in it is a literal), or when one of its operands is a string literal (which is what a mixed expression such as `fallback ?? "https://example.com/" + path` needs).

A `+` that is a *character* of a constant is not concatenation: `"tel:+15551234567"` and `"…?q=swift+ui"` have a fixed value, and so does a raw string such as `#"\(x)"#`, whose `\(` is text. Nor is a chain of plain literals — `"https://example.com/" + "v2/users"` is one constant split across lines. Only the argument's own operators are read, so the `+` in `pages[index + 1]` or `path(for: page + 1)` is never seen, nor is arithmetic in a ternary's condition (`index + 1 < count ? next : last`).

Only the `string:` argument is checked: `URL(fileURLWithPath:)` and `URL(filePath:)` take a path, and interpolating into a path cannot change a scheme, host or query. The safe alternative is `URLComponents`, which applies correct percent-encoding to each component independently and makes the URL structure explicit.

### Known Limitations
- **Only the argument itself is read.** A string built on an earlier line and passed by name — `let text = base + path` then `URL(string: text)` — is not reported, and neither is a concatenation in one branch of a ternary (`flag ? base + path : fallback`), which the parser keeps inside the `?:` operator.
- **A mixed expression with no literal is not reported.** In `fallback ?? base + path` the `+` is a concatenation, but the rule does not resolve operator precedence, so without a literal operand it cannot tell that `+` from the arithmetic in a ternary's condition.

### Non-Violating Examples
```swift
// URLComponents with safe percent-encoding
var components = URLComponents(string: "https://api.example.com")!
components.queryItems = [URLQueryItem(name: "token", value: userToken)]
let url = components.url

// Plain string literal — no interpolation
let url = URL(string: "https://example.com/api")

// A `+` inside a constant is a character of the URL, not an operator
let phone = URL(string: "tel:+15551234567")
let search = URL(string: "https://example.com/search?q=swift+ui")

// Literals joined with `+` are one constant
let endpoint = URL(string: "https://example.com/" + "v2/users")

// The arithmetic belongs to the subscript, not to the URL's text
let next = URL(string: pages[index + 1])

// A file path is not parsed as a URL: interpolation stays part of the path
let scratch = URL(fileURLWithPath: "/tmp/run-\(UUID().uuidString)")
```

### Violating Examples
```swift
let token = "abc123"
let userId = "user456"

let unsafeURL1 = URL(string: "https://example.com/api?token=\(token)")   // interpolation
let unsafeURL2 = URL(string: "https://example.com/api?user=\(userId)")   // interpolation

let unsafeURL3 = URL(string: base + path)                                 // concatenation
let unsafeURL4 = URL(string: "https://example.com/api?q=" + query)       // concatenation
let unsafeURL5 = URL(string: base + "/users/" + userId + "?expand=1")    // concatenation
```

---
