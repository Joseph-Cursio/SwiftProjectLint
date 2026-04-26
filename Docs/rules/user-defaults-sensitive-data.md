# User Defaults Sensitive Data

**Identifier:** `User Defaults Sensitive Data`  
**Severity:** Error  
**Category:** Security  
**Opt-in:** No  
**SwiftLint overlap:** None

## Problem

`UserDefaults` stores data in a plaintext plist file that is:

- **Not encrypted at rest** — the plist is readable by any tool that can access the app's container.
- **Included in device backups** — iCloud and iTunes backups include `UserDefaults` data unless the app explicitly excludes it.
- **Readable within the same app group** — any extension or app sharing the same suite can read the data.

Storing passwords, tokens, API keys, or other secrets in `UserDefaults` is a genuine security vulnerability. The Keychain is the correct storage mechanism for sensitive data.

## Detection

Flags `UserDefaults.standard.set(_:forKey:)` and `UserDefaults(suiteName:...).set(_:forKey:)` calls, and `@AppStorage` property wrapper declarations, where the key string contains a sensitive-sounding name.

Sensitive detection uses a word-boundary heuristic:

1. The key is split into components on camelCase and underscore boundaries.
2. A component exactly matching a sensitive word (`password`, `passwd`, `token`, `secret`, `auth`, `credential`, `passphrase`) triggers a flag.
3. Additionally, full-key exact matches after normalization always trigger a flag: `apiKey`, `accessToken`, `refreshToken`, `privateKey`, `sessionToken`, `authToken`, `bearerToken`.

**False-positive suppression:**

- Keys whose first component is a boolean/verb prefix (`has`, `is`, `did`, `show`, `should`, `will`, `can`, …) are suppressed — they describe UI or tracking state, not secrets.
- Keys where a sensitive component is immediately followed by a non-sensitive qualifier (`count`, `list`, `type`, `index`, `screen`, `name`, …) are suppressed — they describe a property of secrets rather than storing one.

## Examples

```swift
// FLAGGED
UserDefaults.standard.set(apiKey, forKey: "apiKey")
UserDefaults.standard.set(token, forKey: "authToken")
UserDefaults.standard.set(pwd, forKey: "userPassword")
UserDefaults(suiteName: "com.example").set(secret, forKey: "token")
@AppStorage("userPassword") var password: String = ""

// SUPPRESSED — boolean/verb prefix
UserDefaults.standard.set(true, forKey: "hasSeenAuth")
UserDefaults.standard.set(true, forKey: "isTokenExpired")
@AppStorage("showOnboardingToken") var show: Bool = false

// SUPPRESSED — non-sensitive qualifier follows sensitive word
UserDefaults.standard.set(3, forKey: "tokenCount")
UserDefaults.standard.set("Login", forKey: "authScreen")
```

## Suggestion

Use the Keychain (via the `Security` framework or a wrapper like [KeychainAccess](https://github.com/kishikawakatsuki/KeychainAccess)) to store sensitive data:

```swift
// Before — insecure
UserDefaults.standard.set(apiKey, forKey: "apiKey")

// After — secure
try keychain.set(apiKey, key: "apiKey")
```

## Relationship to Other Rules

This rule pairs with **Hardcoded Secret** (`hardcodedSecret`): that rule catches secrets embedded directly in source code; this rule catches secrets persisted to an unencrypted store at runtime.
