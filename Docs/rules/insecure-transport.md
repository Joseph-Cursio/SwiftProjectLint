[← Back to Rules](RULES.md)

## Insecure Transport

**Identifier:** `Insecure Transport`
**Category:** Security
**Severity:** Warning

### Rationale
Using plaintext transport schemes transmits data without encryption, making it vulnerable to man-in-the-middle attacks. While App Transport Security (ATS) blocks most insecure HTTP loads at runtime, other protocols (`ws://`, `ftp://`, `mqtt://`, etc.) are not covered by ATS, making unencrypted connections especially risky.

### Discussion
`InsecureTransportVisitor` inspects every `StringLiteralExprSyntax` node for strings beginning with an insecure scheme (case-insensitive):

| Insecure | Secure equivalent |
|----------|-------------------|
| `http://` | `https://` |
| `ws://` | `wss://` |
| `ftp://` | `sftp://` or `ftps://` |
| `telnet://` | `ssh://` |
| `mqtt://` | `mqtts://` |
| `amqp://` | `amqps://` |
| `redis://` | `rediss://` |
| `ldap://` | `ldaps://` |

It complements the `unsafeURL` rule, which catches interpolated URL construction — this rule covers literal URL strings.

The following are suppressed to reduce false positives:
- **Localhost addresses:** `localhost`, `127.0.0.1`, `[::1]` (local development).
- **RFC 2606 reserved domains:** `example.com`, `example.org`, `example.net`, `example.edu` (documentation examples).
- **Test files:** Files under `/Tests/` or `/XCTests/` directories.
- **Debug blocks:** Strings inside `#if DEBUG` conditional compilation blocks.

### Non-Violating Examples
```swift
// Secure schemes
let endpoint = "https://api.myservice.com/v1/users"
let socket = "wss://chat.myservice.com/connect"
let files = "sftp://files.mycompany.com/uploads"

// Localhost — local development
let devServer = "http://localhost:8080/api"
let devSocket = "ws://localhost:8080/ws"
let devFTP = "ftp://localhost/files"

// Reserved domain — documentation example
let demo = "http://example.com/path"

// Inside #if DEBUG
#if DEBUG
let devURL = "http://dev.myservice.com/api"
#endif
```

### Violating Examples
```swift
// Plaintext HTTP to production endpoints
let endpoint = "http://api.myservice.com/v1/users"
let imageURL = URL(string: "http://cdn.myservice.com/photo.jpg")!

// Unencrypted WebSocket
let socket = "ws://chat.myservice.com/connect"

// Other insecure protocols
let files = "ftp://files.mycompany.com/uploads"
let broker = "mqtt://iot.myservice.com:1883/topic"
```

---
