[← Back to Rules](RULES.md)

## Hardcoded Secret

**Identifier:** `Hardcoded Secret`
**Category:** Security
**Severity:** Error

### Rationale
API keys, passwords, tokens, and other secrets embedded directly in source code are committed to version control, distributed in app binaries, and accessible to anyone who can inspect the binary. A secret leaked through source code is effectively compromised and must be rotated immediately.

### Detection

The rule uses four detection strategies:

1. **Keyword matching:** Variable names containing `apiKey`, `apiSecret`, `secret`, `secretKey`, `password`, `passwd`, `token`, `authKey`, `privateKey`, `encryptionKey`, `signingKey`, `accessKey`, `clientSecret`, `credential`, `bearer`, `passphrase` (case-insensitive). Does **not** flag bare `Key` suffixes (`onboardingKey`, `sortKey`, etc.).

2. **JWT token detection:** String values starting with `eyJ` with three dot-separated segments (the base64-encoded JSON Web Token format).

3. **Known API key prefixes:** String values starting with known service prefixes: `sk-` (OpenAI/Stripe), `pk_live_`/`pk_test_`/`sk_live_`/`sk_test_` (Stripe), `ghp_`/`gho_`/`ghs_` (GitHub), `xoxb-`/`xoxp-` (Slack), `AKIA` (AWS), `AIza` (Google), `SG.` (SendGrid).

4. **Shannon entropy:** For sensitive-named variables, strings of 20+ characters with entropy > 4.0 bits/char are flagged as likely randomly generated secrets.

### Suppression
- Placeholder values: `YOUR_API_KEY_HERE`, `REPLACE_ME`, `TODO`, `CHANGEME`, etc.
- Code inside `#if DEBUG` blocks
- Short strings (< 20 chars) in test files

### Non-Violating Examples
```swift
// Read from Keychain at runtime
let apiKey = KeychainService.shared.retrieve(key: "apiKey")

// Environment variable injected at build time
let token = ProcessInfo.processInfo.environment["API_TOKEN"] ?? ""

// Non-secret key-suffixed variables with string literals — fine
let onboardingKey = "com.myapp.hasCompletedOnboarding"
let sortKey = "name"

// Placeholder values — not flagged
let apiKey = "YOUR_API_KEY_HERE"

// Inside #if DEBUG — compiled out in release
#if DEBUG
let testToken = "test-key-12345"
#endif
```

### Violating Examples
```swift
let apiKey = "sk-12345"              // keyword match
let secret = "topsecret"             // keyword match
let password = "hunter2"             // keyword match
let token = "abcdef"                 // keyword match
let jwtHeader = "eyJhbGci...eyJzdWI...signature"  // JWT detection
let config = "ghp_abcdef1234567890"  // known GitHub token prefix
let awsKey = "AKIAIOSFODNN7EXAMPLE"  // known AWS prefix
```

---
