[<- Back to Rules](RULES.md)

## Logging Sensitive Data

**Identifier:** `Logging Sensitive Data`
**Category:** Security
**Severity:** Warning

### Rationale
Logging passwords, tokens, API keys, or other sensitive values — even with `os.Logger` — can expose them in device logs, crash reports, Console.app, and log aggregation services. Developers often add logging during debugging and forget to remove it or mask the values.

### Discussion
`LoggingSensitiveDataVisitor` detects logging calls (`print`, `debugPrint`, `NSLog`, and `os.Logger` methods) whose arguments reference variables with sensitive names. Sensitive name detection uses camelCase/underscore word-boundary analysis, matching words like `password`, `token`, `secret`, `auth`, `bearer`, `apiKey`, `creditCard`, etc.

The rule suppresses findings when:
- The value uses `os.Logger` with `privacy: .private` (redacted in production)
- The code is inside an `#if DEBUG` block

### Non-Violating Examples
```swift
// Privacy-masked with os.Logger
logger.debug("Token: \(token, privacy: .private)")

// Inside #if DEBUG
#if DEBUG
print("Debug token: \(token)")
#endif

// Non-sensitive variable
print("User name: \(userName)")
```

### Violating Examples
```swift
// Sensitive values in logging calls
print("User token: \(authToken)")
logger.debug("API key = \(apiKey)")
NSLog("Password: %@", password)
print("Bearer: \(bearerToken)")
```

---
