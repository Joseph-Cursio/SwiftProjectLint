[← Back to Rules](RULES.md)

## Hardcoded Secret

**Identifier:** `Hardcoded Secret`
**Category:** Security
**Severity:** Error

### Rationale
API keys, passwords, tokens, and other secrets embedded directly in source code are committed to version control, distributed in app binaries, and accessible to anyone who can inspect the binary. A secret leaked through source code is effectively compromised and must be rotated immediately.

### Discussion
`SecurityVisitor` checks variable declarations whose name contains one of the keywords `apiKey`, `secret`, `password`, `token`, or `key` (case-insensitive). If the initializer is a string literal, an error-severity issue is reported. The fix is to store secrets in the system Keychain, retrieve them from environment variables at build time, or fetch them from a secure remote configuration endpoint at runtime.

### Non-Violating Examples
```swift
// Read from Keychain at runtime
let apiKey = KeychainService.shared.retrieve(key: "apiKey")

// Environment variable injected at build time (Xcode configuration)
let token = ProcessInfo.processInfo.environment["API_TOKEN"] ?? ""
```

### Violating Examples
```swift
let apiKey = "12345"          // hardcoded secret
let secret = "topsecret"      // hardcoded secret
let password = "hunter2"      // hardcoded secret
let token = "abcdef"          // hardcoded secret
```

---
