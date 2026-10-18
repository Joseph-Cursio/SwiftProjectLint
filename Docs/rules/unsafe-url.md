[← Back to Rules](RULES.md)

## Unsafe URL

**Identifier:** `Unsafe URL`
**Category:** Security
**Severity:** Warning

### Rationale
Constructing URLs by splicing in text at run time — string interpolation, `URL(string: "https://example.com/\(path)")`, or concatenation, `URL(string: base + path)` — is unsafe for two reasons: user-controlled input may contain characters that break URL parsing, leading to unexpected behavior; and without percent-encoding, the resulting URL may be malformed or bypass server-side validation.

### Discussion
`SecurityVisitor` reads the `string:` argument of a `URL(...)` call off the syntax tree, wherever its value becomes the URL's text: the whole argument, either side of a `??`, either branch of a `?:`, and inside parentheses at each of them. It reports the argument when one of those parts is:

- **an interpolated string literal** — a literal with an `\(…)` segment. The message says *string interpolation*.
- **a `+` concatenation** — the parser leaves `base + "/" + path` as one flat sequence of operands and operators, and a parenthesised operand as a nested one. The message says *string concatenation*. A `+` read at one of those places is never arithmetic: its result is the URL's text, so `base + path` is reported though nothing in it is a literal.

When more than one part builds text, the first in the source names the finding.

The parser does not resolve operator precedence, so the rule settles the two precedences that decide which operands are text. `?:` binds loosest, so everything before the first one is its condition; `??` binds looser than `+` and a cast, so `configured ?? base + path` falls back to the concatenation, and `value as? String ?? base + path` does too.

What only *chooses* the text is not read. Arithmetic in a ternary's condition — `index + 1 < count ? next : "https://example.com/end"` — is not concatenation, whatever the branches hold, and nor is the `+` in `pages[index + 1]` or `path(for: page + 1)`, which belongs to a subscript or a call. A `+` that is a *character* of a constant is not concatenation either: `"tel:+15551234567"` and `"…?q=swift+ui"` have a fixed value, and so does a raw string such as `#"\(x)"#`, whose `\(` is text. Nor is a chain of plain literals — `"https://example.com/" + "v2/users"` is one constant split across lines, behind a `??` or not.

Only the `string:` argument is checked: `URL(fileURLWithPath:)` and `URL(filePath:)` take a path, and interpolating into a path cannot change a scheme, host or query. The safe alternative is `URLComponents`, which applies correct percent-encoding to each component independently and makes the URL structure explicit.

### Known Limitations
- **Only the argument itself is read.** A string built on an earlier line and passed by name — `let text = base + path` then `URL(string: text)` — is not reported, nor is one built by a call such as `base.appending(path)`.
- **Only `+`, `??`, casts and `?:` are taken apart.** Settling any other operator needs its precedence, so a part of the argument that holds one is not read: neither `base + path as String` nor `base <> path`, with a custom operator, is reported.

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

// The arithmetic is the ternary's condition: it chooses the URL, it is no part of it
let page = URL(string: index + 1 < count ? nextPageURL : "https://example.com/end")

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

let unsafeURL6 = URL(string: configured ?? base + path)                   // concatenation
let unsafeURL7 = URL(string: flag ? "https://example.com/\(path)" : home) // interpolation
```

---
