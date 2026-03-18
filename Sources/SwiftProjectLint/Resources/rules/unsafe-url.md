[← Back to Rules](RULES.md)

## Unsafe URL

**Identifier:** `Unsafe URL`
**Category:** Security
**Severity:** Warning

### Rationale
Constructing URLs with string interpolation — `URL(string: "https://example.com/\(path)")` — is unsafe for two reasons: user-controlled input may contain characters that break URL parsing, leading to unexpected behavior; and without percent-encoding, the resulting URL may be malformed or bypass server-side validation.

### Discussion
`SecurityVisitor` detects `URL(string:)` calls where the string argument contains `\(` (string interpolation) or `+` (concatenation). The safe alternative is `URLComponents`, which applies correct percent-encoding to each component independently and makes the URL structure explicit.

### Non-Violating Examples
```swift
// URLComponents with safe percent-encoding
var components = URLComponents(string: "https://api.example.com")!
components.queryItems = [URLQueryItem(name: "token", value: userToken)]
let url = components.url

// Plain string literal — no interpolation
let url = URL(string: "https://example.com/api")
```

### Violating Examples
```swift
let token = "abc123"
let userId = "user456"

let unsafeURL1 = URL(string: "https://example.com/api?token=\(token)")   // interpolation
let unsafeURL2 = URL(string: "https://example.com/api?user=\(userId)")   // interpolation
```

---
