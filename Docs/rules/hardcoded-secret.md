[← Back to Rules](RULES.md)

## Hardcoded Secret

**Identifier:** `Hardcoded Secret`
**Category:** Security
**Severity:** Error

### Rationale
API keys, passwords, tokens, and other secrets embedded directly in source code are committed to version control, distributed in app binaries, and accessible to anyone who can inspect the binary. A secret leaked through source code is effectively compromised and must be rotated immediately.

### Scope
Flags a variable declaration with a string literal initializer when the variable name contains any of these keywords (case-insensitive):

- `apiKey`, `apiSecret`
- `secret`, `secretKey`, `clientSecret`, `secretAccessKey`
- `password`, `passwd`
- `token`
- `authKey`, `privateKey`, `encryptionKey`, `signingKey`, `accessKey`
- `credential`

Does **not** flag variables that merely end in `Key` — names like `onboardingKey`, `sortKey`, `cacheKey`, or `primaryKey` are not secret indicators and are excluded.

### Non-Violating Examples
```swift
// Read from Keychain at runtime
let apiKey = KeychainService.shared.retrieve(key: "apiKey")

// Environment variable injected at build time
let token = ProcessInfo.processInfo.environment["API_TOKEN"] ?? ""

// Non-secret key-suffixed variables with string literals — fine
let onboardingKey = "com.myapp.hasCompletedOnboarding"
let sortKey = "name"
let cacheKey = "user_profile"
```

### Violating Examples
```swift
let apiKey = "sk-12345"              // hardcoded API key
let secret = "topsecret"             // hardcoded secret
let password = "hunter2"             // hardcoded password
let token = "abcdef"                 // hardcoded token
let clientSecret = "cs_live_xyz"     // hardcoded client secret
let credential = "user:pass"         // hardcoded credential
```

---
