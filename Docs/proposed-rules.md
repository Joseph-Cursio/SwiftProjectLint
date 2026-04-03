# Proposed New Rules & Rule Modifications

This document contains detailed proposals for new linting rules and modifications to existing rules. Each proposal includes detection logic, severity rationale, example code, and implementation notes.

## SwiftLint Overlap Summary

Each rule is annotated with its SwiftLint overlap status:
- **No SwiftLint equivalent** — entirely unique to SwiftProjectLint
- **Partial overlap** — SwiftLint has a related rule but SPL adds significant value (details noted)
- **Full overlap** — SwiftLint already covers this; rule marked as superseded

Of the 30 proposals below, **23 have no SwiftLint equivalent**, **6 have partial overlap** where SPL adds SwiftUI-awareness / cross-file analysis / semantic depth, and **1 is fully covered** by SwiftLint.

---

## Table of Contents

### New Rules
- [Concurrency](#concurrency)
  - [unchecked-sendable](#unchecked-sendable)
  - [global-actor-mismatch](#global-actor-mismatch)
  - [main-actor-missing-on-ui-code](#main-actor-missing-on-ui-code)
  - [unbounded-task-group](#unbounded-task-group)
- [Performance](#performance)
  - [formatter-in-view-body](#formatter-in-view-body)
  - [image-without-resizable](#image-without-resizable)
  - [on-receive-without-debounce](#on-receive-without-debounce)
- [Security](#security)
  - [insecure-transport](#insecure-transport)
  - [user-defaults-sensitive-data](#user-defaults-sensitive-data)
  - [logging-sensitive-data](#logging-sensitive-data)
- [Accessibility](#accessibility)
  - [tap-target-too-small](#tap-target-too-small)
  - [missing-dynamic-type-support](#missing-dynamic-type-support)
  - [decorative-image-missing-trait](#decorative-image-missing-trait)
- [Architecture](#architecture)
  - [god-view-model](#god-view-model)
  - [view-model-direct-db-access](#view-model-direct-db-access)
  - [circular-dependency](#circular-dependency)
- [Code Quality](#code-quality)
  - [redundant-binding](#redundant-binding)
  - [string-switch-over-enum](#string-switch-over-enum)
  - [nested-generic-complexity](#nested-generic-complexity)
- [Modernization](#modernization)
  - [legacy-string-format](#legacy-string-format)
  - [legacy-array-init](#legacy-array-init)
  - [legacy-closure-syntax](#legacy-closure-syntax)
  - [ios17-observation-migration](#ios17-observation-migration)

### Modifications to Existing Rules
- [hardcoded-secret (expand)](#hardcoded-secret-expand)
- [magic-number (add boolean sub-rule)](#magic-number-add-boolean-sub-rule)
- [law-of-demeter (SwiftUI exemptions)](#law-of-demeter-swiftui-exemptions)
- [single-implementation-protocol (test-aware)](#single-implementation-protocol-test-aware)
- [print-statement (debug-aware)](#print-statement-debug-aware)
- [missing-preview (tiered severity)](#missing-preview-tiered-severity)
- [for-each-self-id (expand to hashValue)](#for-each-self-id-expand-to-hashvalue)

---

## New Rules

---

## Concurrency

### unchecked-sendable

**Rule Identifier:** `uncheckedSendable`
**Category:** `.codeQuality`
**Severity:** `.warning`
**Opt-in:** No
**SwiftLint overlap:** None. `redundant_sendable` flags redundant `Sendable` conformances, not `@unchecked`. No built-in rule detects `@unchecked Sendable`.

#### Problem

`@unchecked Sendable` tells the compiler to trust the developer that a type is safe to pass across concurrency boundaries. In practice, this is frequently used as a quick fix to silence compiler errors without actually ensuring thread safety. Under Swift 6 strict concurrency, these become landmines — the compiler can't help you find data races in types marked this way.

#### Detection Logic

**Visitor type:** `SyntaxVisitor` overriding `visit(_ node: ClassDeclSyntax)` and `visit(_ node: StructDeclSyntax)`

1. Walk inheritance clauses looking for `Sendable` in the inherited type list.
2. Check whether the declaration or the `Sendable` conformance is annotated with `@unchecked`.
3. Specifically detect the pattern `@unchecked Sendable` in the inheritance clause.
4. **Suppress** if the type contains a recognized synchronization primitive as a stored property:
   - `OSAllocatedUnfairLock`, `Mutex`, `NSLock`, `NSRecursiveLock`, `DispatchQueue` (used as a serial queue), `pthread_mutex_t`
   - This mirrors the smart suppression already used by the `nonisolatedUnsafe` rule.
5. **Suppress** for types that are wrappers around a single `Sendable`-conforming stored property (the conformance is trivially correct).

#### Examples

```swift
// FLAGGED: No synchronization primitive present
class NetworkCache: @unchecked Sendable {
    var cache: [String: Data] = [:]  // Unprotected mutable state
}

// SUPPRESSED: Has a recognized lock
class ThreadSafeCache: @unchecked Sendable {
    private let lock = OSAllocatedUnfairLock()
    private var cache: [String: Data] = [:]
}

// SUPPRESSED: Single immutable stored property
struct Wrapper: @unchecked Sendable {
    let value: Int
}
```

#### Message Template
`"@unchecked Sendable on '{typeName}' bypasses the compiler's data-race safety checks"`

#### Suggestion
`"Ensure thread safety with a lock or actor, or remove @unchecked and fix the resulting compiler errors to get real safety guarantees."`

#### Implementation Notes
- Reuse the lock-detection logic from `NonisolatedUnsafeVisitor` (consider extracting into a shared utility on `BasePatternVisitor`).
- Could be extended later to detect `nonisolated(unsafe)` + `@unchecked Sendable` on the same type (double bypass — higher severity).

---

### global-actor-mismatch

**Rule Identifier:** `globalActorMismatch`
**Category:** `.codeQuality`
**Severity:** `.warning`
**Opt-in:** No
**SwiftLint overlap:** Partial — `incompatible_concurrency_annotation` (opt-in) flags missing `@preconcurrency` annotations for Swift 5 compat. It does NOT detect cross-actor calls missing `await`. SPL adds semantic cross-actor call analysis.

#### Problem

When a function isolated to one global actor calls a function isolated to a different global actor (or no actor) without `await`, it causes a compiler error under strict concurrency. But in Swift 5 mode with `@preconcurrency`, these can be silent. Detecting them early surfaces migration issues before turning on strict concurrency.

#### Detection Logic

**Visitor type:** `SyntaxVisitor` with state tracking for the current isolation context.

1. Track the current isolation context as a stack:
   - When entering a class/struct/enum annotated with `@MainActor` (or any `@globalActor`), push that actor onto the stack.
   - When entering a function annotated with a different global actor, push that.
   - Pop on exit.
2. When visiting a `FunctionCallExprSyntax`:
   - Resolve the callee to a declaration (if available via the file's AST — this is best-effort without full type checking).
   - If the callee is annotated with a *different* global actor than the current context, and the call is not preceded by `await`, flag it.
3. **Limitation:** Without full type information, this rule is best-effort. It should focus on obvious cases:
   - Calls to methods on types annotated with `@MainActor` from a non-`@MainActor` context (or vice versa).
   - Calls to free functions with explicit actor annotations.

#### Examples

```swift
@MainActor
class ViewModel {
    func updateUI() { /* ... */ }
}

// FLAGGED: Calling @MainActor method without await from non-isolated context
func processData(viewModel: ViewModel) {
    viewModel.updateUI()  // Missing await
}

// OK: Properly awaited
func processDataAsync(viewModel: ViewModel) async {
    await viewModel.updateUI()
}
```

#### Message Template
`"Call to '{functionName}' may cross actor boundaries without 'await'"`

#### Suggestion
`"Add 'await' before the call, or ensure both the caller and callee share the same actor isolation."`

#### Implementation Notes
- This is a heuristic rule — it cannot fully replicate the compiler's isolation checking without type information. Position it as a "likely issue" detector, not a guarantee.
- Consider making this opt-in initially until the false-positive rate is understood.
- Cross-file analysis could improve accuracy by building a map of actor-annotated types across the project.

---

### main-actor-missing-on-ui-code

**Rule Identifier:** `mainActorMissingOnUICode`
**Category:** `.codeQuality`
**Severity:** `.warning`
**Opt-in:** No
**SwiftLint overlap:** None. No SwiftLint rule checks whether `ObservableObject` subclasses have `@MainActor` isolation.

#### Problem

View model classes that publish state changes to SwiftUI views must do so on the main thread. Without `@MainActor` isolation, `@Published` property mutations from background contexts cause UI updates on background threads — leading to undefined behavior, visual glitches, or crashes. This is one of the most common concurrency bugs in SwiftUI apps.

#### Detection Logic

**Visitor type:** `SyntaxVisitor` overriding `visit(_ node: ClassDeclSyntax)`

1. Identify classes that conform to `ObservableObject` (check inheritance clause).
2. Check whether the class has at least one `@Published` property.
3. If both conditions are met, check whether the class is annotated with `@MainActor`.
4. If not annotated, flag the class.
5. **Suppress** if:
   - The class is already annotated with `@MainActor`.
   - The class is nested inside a `@MainActor`-annotated type (inherited isolation).
   - Every `@Published` property setter is individually annotated with `@MainActor` (granular isolation).

#### Examples

```swift
// FLAGGED: ObservableObject with @Published but no @MainActor
class SettingsViewModel: ObservableObject {
    @Published var userName: String = ""
    @Published var isLoading: Bool = false

    func loadData() async {
        isLoading = true  // Could be called from background
        // ...
    }
}

// OK: Properly isolated
@MainActor
class SettingsViewModel: ObservableObject {
    @Published var userName: String = ""
    @Published var isLoading: Bool = false
}

// OK: Uses @Observable (no @Published needed, different model)
@Observable
class SettingsViewModel {
    var userName: String = ""
}
```

#### Message Template
`"'{className}' conforms to ObservableObject with @Published properties but lacks @MainActor isolation"`

#### Suggestion
`"Add @MainActor to the class declaration to ensure @Published property mutations happen on the main thread, or migrate to @Observable."`

#### Implementation Notes
- This rule naturally pairs with `legacyObservableObject` — if you're flagging missing `@MainActor`, you might also suggest migrating to `@Observable` entirely.
- The visitor needs to track whether it's inside a `@MainActor`-annotated parent to handle inherited isolation.
- This is a high-value rule: it catches one of the most common sources of SwiftUI crashes.

---

### unbounded-task-group

**Rule Identifier:** `unboundedTaskGroup`
**Category:** `.performance`
**Severity:** `.warning`
**Opt-in:** No
**SwiftLint overlap:** None. No SwiftLint rule analyzes task group concurrency patterns.

#### Problem

`withTaskGroup` and `withThrowingTaskGroup` are powerful structured concurrency primitives, but when tasks are added in a loop without limiting concurrency, the runtime may spawn thousands of concurrent tasks. This exhausts thread pool resources, causes memory pressure, and can deadlock the cooperative thread pool.

#### Detection Logic

**Visitor type:** `SyntaxVisitor` with scope tracking

1. Detect `withTaskGroup` or `withThrowingTaskGroup` call expressions.
2. Inside the trailing closure, look for `group.addTask` calls within a `for` loop or `while` loop.
3. Check whether there is a corresponding `group.next()` call (or `for await` over the group) *inside the same loop* that would provide backpressure.
4. If `addTask` is in a loop without backpressure, flag it.
5. **Suppress** if:
   - The loop iterates over a collection with a known small size (e.g., literal array, `0..<5`).
   - There's a `group.next()` call inside the loop body (manual throttling pattern).

#### Examples

```swift
// FLAGGED: Unbounded task creation
await withTaskGroup(of: Data.self) { group in
    for url in urls {  // 'urls' could have 10,000 elements
        group.addTask {
            try await fetchData(from: url)
        }
    }
    for await result in group { /* ... */ }
}

// OK: Manual backpressure with group.next()
await withTaskGroup(of: Data.self) { group in
    let maxConcurrency = 10
    for (index, url) in urls.enumerated() {
        if index >= maxConcurrency {
            _ = await group.next()  // Wait before adding more
        }
        group.addTask {
            try await fetchData(from: url)
        }
    }
}
```

#### Message Template
`"Task group adds tasks in a loop without concurrency limiting — may exhaust thread pool resources"`

#### Suggestion
`"Add backpressure by calling 'group.next()' inside the loop, or limit concurrency with a counter. Consider using a bounded task group pattern."`

#### Implementation Notes
- The detection is scope-sensitive: need to track that we're inside a `withTaskGroup` closure, then inside a loop, then see `addTask` without `next()`.
- Use a state machine in the visitor: `idle` → `inTaskGroup` → `inLoopInsideTaskGroup`.
- This pattern is well-documented by Apple and the Swift concurrency team as a common footgun.

---

## Performance

### formatter-in-view-body

**Rule Identifier:** `formatterInViewBody`
**Category:** `.performance`
**Severity:** `.warning`
**Opt-in:** No
**SwiftLint overlap:** None. SwiftLint has no SwiftUI body-specific performance rules.

#### Problem

`DateFormatter`, `NumberFormatter`, `ISO8601DateFormatter`, `ByteCountFormatter`, `MeasurementFormatter`, `PersonNameComponentsFormatter`, and `JSONDecoder`/`JSONEncoder` are expensive to create. When instantiated inside a SwiftUI view's `body` property, they are recreated on every view re-render. This is one of the most common and impactful SwiftUI performance mistakes.

#### Detection Logic

**Visitor type:** `SyntaxVisitor` with scope tracking

1. Track when we're inside a computed property named `body` on a type conforming to `View` (use the same heuristic as `expensiveOperationInViewBody`).
2. Inside that scope, detect instantiation of known expensive types:
   - `DateFormatter()`, `NumberFormatter()`, `ISO8601DateFormatter()`
   - `ByteCountFormatter()`, `MeasurementFormatter()`, `PersonNameComponentsFormatter()`
   - `JSONDecoder()`, `JSONEncoder()`
   - `NSRegularExpression(...)`, `try! NSRegularExpression(...)`
   - `DateComponentsFormatter()`
3. Also flag `Date.FormatStyle(...)` and `.formatted(...)` calls that create new format styles each time (though these are lighter than Foundation formatters, they still allocate).
4. **Suppress** if:
   - The formatter is assigned to a `static` property (correct pattern).
   - The formatter is inside a `let` at file/type scope (stored, not recomputed).

#### Examples

```swift
struct EventRow: View {
    let event: Event

    var body: some View {
        // FLAGGED: DateFormatter created every render
        let formatter = DateFormatter()
        formatter.dateStyle = .medium

        Text(formatter.string(from: event.date))
    }
}

// CORRECT: Static formatter
struct EventRow: View {
    private static let dateFormatter: DateFormatter = {
        let fmt = DateFormatter()
        fmt.dateStyle = .medium
        return fmt
    }()

    var body: some View {
        Text(Self.dateFormatter.string(from: event.date))
    }
}
```

#### Message Template
`"'{formatterType}' instantiated inside view body — recreated on every render"`

#### Suggestion
`"Move the formatter to a static property or to the view's initializer. Foundation formatters are expensive to create and should be reused."`

#### Implementation Notes
- This is closely related to the existing `expensiveOperationInViewBody` rule. Consider whether to extend that rule or create a separate one. A separate rule allows independent severity configuration and a more specific message.
- The set of expensive types should be defined as a constant set in the visitor for easy extension.
- Could later be extended to detect `Locale(identifier:)` and `Calendar(identifier:)` allocations in `body`.

---

### image-without-resizable

**Rule Identifier:** `imageWithoutResizable`
**Category:** `.uiPatterns`
**Severity:** `.info`
**Opt-in:** No
**SwiftLint overlap:** None. No SwiftLint rule checks SwiftUI `Image` modifier chains.

#### Problem

Applying `.frame()` to an `Image` without first calling `.resizable()` has no effect on the image size — the image renders at its intrinsic size and the frame just adds empty space around it. This is a very common SwiftUI beginner mistake and a frequent source of layout bugs.

#### Detection Logic

**Visitor type:** `SyntaxVisitor` tracking modifier chains

1. Detect `Image(...)` or `Image(systemName:)` expressions.
2. Follow the modifier chain on the image.
3. If `.frame(width:height:)` or `.frame(minWidth:maxWidth:...)` appears without a preceding `.resizable()` in the chain, flag it.
4. **Suppress** if:
   - `.resizable()` appears anywhere before `.frame()` in the chain.
   - The image is an SF Symbol (these scale differently, though `.resizable()` is still best practice).
   - The image is used inside a `Label` (the label handles sizing).

#### Examples

```swift
// FLAGGED: frame without resizable
Image("hero")
    .frame(width: 200, height: 100)

// OK: resizable before frame
Image("hero")
    .resizable()
    .frame(width: 200, height: 100)

// OK: aspectRatio implies resizable intent (could still flag)
Image("hero")
    .resizable()
    .aspectRatio(contentMode: .fit)
    .frame(width: 200)
```

#### Message Template
`"Image with .frame() but no .resizable() — image will render at intrinsic size"`

#### Suggestion
`"Add .resizable() before .frame() to allow the image to scale to the specified dimensions."`

#### Implementation Notes
- Modifier chain analysis is already used by `modifierOrderIssue` — reuse or share that logic.
- This is a layout-correctness rule as much as a performance rule. Category `.uiPatterns` is more appropriate.

---

### on-receive-without-debounce

**Rule Identifier:** `onReceiveWithoutDebounce`
**Category:** `.performance`
**Severity:** `.info`
**Opt-in:** Yes
**SwiftLint overlap:** None. No SwiftLint rule analyzes Combine publisher patterns in SwiftUI.

#### Problem

`.onReceive()` with a high-frequency publisher (like `Timer.publish`, `NotificationCenter.publisher`, or a Combine subject updated rapidly) can trigger view updates at a rate that degrades performance. Adding `.debounce()`, `.throttle()`, or `.receive(on:)` helps control update frequency.

#### Detection Logic

**Visitor type:** `SyntaxVisitor`

1. Detect `.onReceive(` modifier calls.
2. Check the publisher argument for known high-frequency sources:
   - `Timer.publish(every:` with interval < 1.0 second
   - `NotificationCenter.default.publisher(for:` with known high-frequency notifications (e.g., `.NSWorkspaceDidActivateApplication`, keyboard notifications)
   - Any publisher chained with `.sink` in rapid succession
3. Check whether the publisher chain includes `.debounce(`, `.throttle(`, or `.collect(` before `.onReceive`.
4. If a high-frequency source has no rate-limiting operator, flag it.

#### Examples

```swift
// FLAGGED: Timer at 60fps with no throttling
.onReceive(Timer.publish(every: 0.016, on: .main, in: .common).autoconnect()) { _ in
    updatePosition()
}

// OK: Debounced
.onReceive(
    searchText.publisher
        .debounce(for: .milliseconds(300), scheduler: RunLoop.main)
) { text in
    performSearch(text)
}
```

#### Message Template
`"High-frequency publisher in .onReceive() without rate limiting — may cause excessive view updates"`

#### Suggestion
`"Add .debounce(for:scheduler:), .throttle(for:scheduler:latest:), or .collect(.byTime(...)) to limit update frequency."`

#### Implementation Notes
- Opt-in because the heuristic for "high-frequency" is imperfect. Users who intentionally use high-frequency updates (e.g., game loops) would find this noisy.
- The `animationInHighFrequencyUpdate` rule already detects `.animation()` near `onReceive` — this is a complementary rule about the `onReceive` itself.

---

## Security

### insecure-transport

**Rule Identifier:** `insecureTransport`
**Category:** `.security`
**Severity:** `.warning`
**Opt-in:** No
**SwiftLint overlap:** None. No built-in SwiftLint rule detects `http://` URL literals. Could be approximated with `custom_rules` regex, but no built-in rule exists.

#### Problem

Using `http://` instead of `https://` transmits data in plaintext, making it vulnerable to man-in-the-middle attacks. While App Transport Security (ATS) blocks most insecure loads at runtime, hardcoded `http://` URLs often indicate an intentional ATS exception or a development oversight that should be reviewed.

#### Detection Logic

**Visitor type:** `SyntaxVisitor` overriding `visit(_ node: StringLiteralExprSyntax)`

1. Extract the string literal content.
2. Check if it matches the pattern `http://` (case-insensitive) at the start.
3. **Suppress** if:
   - The URL is `http://localhost`, `http://127.0.0.1`, or `http://[::1]` (local development).
   - The URL is in a comment or documentation string.
   - The string is inside a test target (detected by file path containing `/Tests/` or `/XCTests/`).
   - The URL is `http://example.com` or other RFC 2606 reserved domains (documentation examples).
   - The URL appears in an `#if DEBUG` block.

#### Examples

```swift
// FLAGGED
let endpoint = "http://api.myservice.com/v1/users"
let imageURL = URL(string: "http://cdn.example.org/photo.jpg")!

// SUPPRESSED: localhost
let devServer = "http://localhost:8080/api"

// SUPPRESSED: test file
// In Tests/NetworkTests/APITests.swift
let mockURL = "http://test-server.internal/mock"
```

#### Message Template
`"Insecure HTTP URL detected: '{url}' — data transmitted in plaintext"`

#### Suggestion
`"Use https:// for secure communication. If HTTP is intentionally required, document the reason and ensure an ATS exception is configured."`

#### Implementation Notes
- Pair with `unsafeURL` which catches interpolated URLs — this rule covers literal URLs.
- Could also detect `NSAppTransportSecurity` / `NSAllowsArbitraryLoads` in Info.plist files (would need to parse plist XML, out of scope for AST visitors but could be a separate file-content scanner).

---

### user-defaults-sensitive-data

**Rule Identifier:** `userDefaultsSensitiveData`
**Category:** `.security`
**Severity:** `.error`
**Opt-in:** No
**SwiftLint overlap:** None. No SwiftLint rule checks what is stored in UserDefaults.

#### Problem

`UserDefaults` stores data in a plaintext plist file that is not encrypted at rest, is included in device backups, and is readable by any process with the same sandbox. Storing passwords, tokens, API keys, or other secrets in `UserDefaults` is a significant security vulnerability. The Keychain is the correct storage mechanism for sensitive data.

#### Detection Logic

**Visitor type:** `SyntaxVisitor` overriding `visit(_ node: FunctionCallExprSyntax)`

1. Detect calls to `UserDefaults.standard.set(` or `UserDefaults(...).set(`.
2. Also detect `@AppStorage(` property wrapper declarations.
3. Check the key argument (the `forKey:` parameter or the `@AppStorage` string) for sensitive-sounding names:
   - Exact matches: `"password"`, `"token"`, `"secret"`, `"apiKey"`, `"api_key"`, `"accessToken"`, `"access_token"`, `"refreshToken"`, `"refresh_token"`, `"privateKey"`, `"private_key"`, `"credential"`, `"auth"`, `"sessionToken"`, `"session_token"`
   - Case-insensitive substring matches: `password`, `token`, `secret`, `apikey`, `credential`, `auth`
4. Also detect the value being stored if it comes from a variable with a sensitive name.
5. **Suppress** if the key is something like `"showOnboardingToken"` or `"tokenCount"` where the sensitive substring is part of a non-sensitive compound word. Use word-boundary heuristics (camelCase boundary, underscore boundary).

#### Examples

```swift
// FLAGGED
UserDefaults.standard.set(apiKey, forKey: "apiKey")
UserDefaults.standard.set(token, forKey: "authToken")
@AppStorage("userPassword") var password: String = ""

// SUPPRESSED: Non-sensitive compound word
UserDefaults.standard.set(count, forKey: "tokenCount")
@AppStorage("hasSeenAuthentication") var hasSeen: Bool = false
```

#### Message Template
`"Sensitive data key '{key}' stored in UserDefaults — not encrypted at rest"`

#### Suggestion
`"Use the Keychain (via Security framework or a wrapper like KeychainAccess) to store sensitive data like passwords, tokens, and API keys."`

#### Implementation Notes
- The word-boundary heuristic is critical to avoid false positives. Split on camelCase boundaries and underscores, then check if any individual word is sensitive.
- `.error` severity is justified: storing secrets in plaintext is a genuine security vulnerability, not a style concern.
- This pairs well with `hardcodedSecret` — that rule catches secrets in source code, this one catches secrets being persisted insecurely.

---

### logging-sensitive-data

**Rule Identifier:** `loggingSensitiveData`
**Category:** `.security`
**Severity:** `.warning`
**Opt-in:** No
**SwiftLint overlap:** None. No SwiftLint rule performs data-flow analysis on print/log arguments.

#### Problem

Logging passwords, tokens, API keys, or other sensitive values — even with `os.Logger` — can expose them in device logs, crash reports, Console.app, and log aggregation services. Developers often add logging during debugging and forget to remove it or mask the values.

#### Detection Logic

**Visitor type:** `SyntaxVisitor` overriding `visit(_ node: FunctionCallExprSyntax)`

1. Detect logging calls:
   - `print(...)`, `debugPrint(...)`, `NSLog(...)`
   - `Logger.(...).log(...)`, `Logger.(...).debug(...)`, `Logger.(...).info(...)`, `Logger.(...).error(...)`
   - `os_log(...)`
2. Inspect the arguments for references to variables with sensitive names:
   - Same sensitive name list as `userDefaultsSensitiveData`.
   - Also match: `bearer`, `authorization`, `cookie`, `ssn`, `socialSecurity`, `creditCard`, `cvv`
3. Check string interpolation segments in the log message for sensitive variable names.
4. **Suppress** if:
   - The value is wrapped in `String(repeating: "*", count:)` or similar masking.
   - The log uses `os.Logger` with `.private` privacy level: `\(secret, privacy: .private)`.
   - The call is inside an `#if DEBUG` block.

#### Examples

```swift
// FLAGGED
print("User token: \(authToken)")
logger.debug("API key = \(apiKey)")
NSLog("Password: %@", password)

// SUPPRESSED: Privacy-masked
logger.debug("Token: \(token, privacy: .private)")

// SUPPRESSED: Inside #if DEBUG
#if DEBUG
print("Debug token: \(token)")
#endif
```

#### Message Template
`"Potentially sensitive value '{variableName}' passed to logging function"`

#### Suggestion
`"Remove sensitive data from logs, or use os.Logger with privacy: .private to redact in production. Wrap in #if DEBUG if needed only during development."`

#### Implementation Notes
- The existing `printStatement` rule already flags `print()` calls generically. This rule is complementary — it flags the *specific* danger of logging sensitive values, even when using proper logging frameworks.
- Variable name matching should use the same word-boundary heuristic as `userDefaultsSensitiveData`.

---

## Accessibility

### tap-target-too-small

**Rule Identifier:** `tapTargetTooSmall`
**Category:** `.accessibility`
**Severity:** `.warning`
**Opt-in:** No
**SwiftLint overlap:** None. No SwiftLint rule analyzes SwiftUI frame sizes on interactive elements.

#### Problem

Apple's Human Interface Guidelines and WCAG 2.1 Success Criterion 2.5.5 recommend a minimum tap target size of 44×44 points. Interactive elements smaller than this are difficult for users with motor impairments, large fingers, or assistive devices to activate reliably.

#### Detection Logic

**Visitor type:** `SyntaxVisitor` tracking modifier chains on interactive elements

1. Identify interactive elements: `Button`, `Toggle`, `Stepper`, `Slider`, `Link`, `NavigationLink`, `Menu`, `.onTapGesture`.
2. Follow the modifier chain for `.frame(width:height:)` or `.frame(maxWidth:maxHeight:)`.
3. If either `width` or `height` is a numeric literal less than 44, flag it.
4. Also check `.contentShape(Rectangle())` with a `.frame()` — if the content shape is constrained, the actual tap target may be smaller.
5. **Suppress** if:
   - `.frame()` is followed by `.padding()` that would bring the total size above 44pt.
   - The element has `.contentShape(Rectangle())` applied after a larger `.frame()`.
   - The element is inside a `.toolbar` or `.navigationBarItems` (system handles sizing).

#### Examples

```swift
// FLAGGED: 30x30 is below the 44pt minimum
Button(action: { dismiss() }) {
    Image(systemName: "xmark")
}
.frame(width: 30, height: 30)

// OK: Meets minimum
Button(action: { dismiss() }) {
    Image(systemName: "xmark")
}
.frame(width: 44, height: 44)

// OK: Small visual frame but large tap target
Button(action: { dismiss() }) {
    Image(systemName: "xmark")
        .frame(width: 20, height: 20)
}
.frame(width: 44, height: 44)
.contentShape(Rectangle())
```

#### Message Template
`"Interactive element has frame {width}×{height}pt — below the 44pt minimum tap target size"`

#### Suggestion
`"Increase the frame to at least 44×44pt, or add .padding() and .contentShape(Rectangle()) to expand the tap target without changing the visual size."`

#### Implementation Notes
- Only flag when *both* dimensions are explicitly constrained and at least one is < 44. If only width is set, the height may be system-determined and fine.
- This rule can produce false positives when padding enlarges the effective tap area. The suppression for `.padding()` should be conservative — only suppress if the padding + frame clearly exceeds 44pt.

---

### missing-dynamic-type-support

**Rule Identifier:** `missingDynamicTypeSupport`
**Category:** `.accessibility`
**Severity:** `.info`
**Opt-in:** Yes
**SwiftLint overlap:** None. No SwiftLint rule checks `lineLimit` interaction with Dynamic Type.

#### Problem

`.lineLimit(1)` on text elements can cause truncation when users select larger Dynamic Type sizes. This makes content inaccessible to users who rely on larger text. Views should generally allow text to flow onto multiple lines or provide scroll behavior for accessibility.

#### Detection Logic

**Visitor type:** `SyntaxVisitor`

1. Detect `.lineLimit(1)` or `.lineLimit(0)` (zero means unlimited — don't flag) modifiers.
2. Check if the modified element contains `Text` with dynamic content (string interpolation, variables — not short static labels).
3. **Suppress** if:
   - The text is clearly a short label (e.g., `Text("OK")`, `Text("Cancel")`).
   - The view has `.minimumScaleFactor()` applied (text will shrink before truncating).
   - The view has `.truncationMode(.tail)` with `.accessibilityLabel()` that provides the full text.
   - The text is inside a `NavigationLink` or table cell where truncation is expected.

#### Examples

```swift
// FLAGGED: Long dynamic text with lineLimit(1)
Text(article.title)
    .lineLimit(1)

// SUPPRESSED: Has minimumScaleFactor
Text(article.title)
    .lineLimit(1)
    .minimumScaleFactor(0.5)

// SUPPRESSED: Short static label
Text("Save")
    .lineLimit(1)
```

#### Message Template
`"'.lineLimit(1)' on dynamic text may truncate content at larger Dynamic Type sizes"`

#### Suggestion
`"Consider allowing multiple lines, adding .minimumScaleFactor(), or providing the full text via .accessibilityLabel()."`

#### Implementation Notes
- Opt-in because `.lineLimit(1)` is legitimate in many UI designs (table rows, list cells). This rule is most useful for content-heavy views.
- Detecting "short static label" vs. "dynamic content" requires checking whether the `Text` initializer uses a string literal under ~20 characters vs. a variable/interpolation.

---

### decorative-image-missing-trait

**Rule Identifier:** `decorativeImageMissingTrait`
**Category:** `.accessibility`
**Severity:** `.info`
**Opt-in:** Yes
**SwiftLint overlap:** Partial — `accessibility_label_for_image` (opt-in) flags images without accessibility labels. It does NOT distinguish decorative vs. meaningful images or check for `.accessibilityHidden(true)`. SPL adds context-aware detection for decorative images specifically.

#### Problem

Decorative images (backgrounds, dividers, visual flourishes) that lack `.accessibilityHidden(true)` are announced by VoiceOver, creating noise for screen reader users. Images that don't convey information should be explicitly hidden from the accessibility tree.

#### Detection Logic

**Visitor type:** `SyntaxVisitor`

1. Detect `Image(...)` expressions (not `Image(systemName:)` which are more likely semantic).
2. Check the modifier chain for the *absence* of:
   - `.accessibilityHidden(true)`
   - `.accessibilityLabel(...)` (if it has a label, it's intentionally accessible)
   - `.accessibilityElement(children: .combine)` or similar
3. Check if the image is used in a context suggesting decoration:
   - Inside `.background()` or `.overlay()` modifiers
   - Named with decorative-sounding names: `"background"`, `"divider"`, `"pattern"`, `"gradient"`
   - Applied with `.opacity()` less than 1.0
4. Flag images in decorative contexts that lack accessibility handling.
5. **Suppress** if the image is inside a `Button` or `Label` (it's likely meaningful, covered by `iconOnlyButtonMissingLabel`).

#### Examples

```swift
// FLAGGED: Decorative background image without accessibility handling
Image("headerBackground")
    .resizable()
    .frame(height: 200)

ZStack {
    Image("pattern")  // FLAGGED: likely decorative
        .opacity(0.3)
    content
}

// OK: Explicitly hidden
Image("headerBackground")
    .resizable()
    .accessibilityHidden(true)

// OK: Has a meaningful label
Image("chart")
    .accessibilityLabel("Sales chart showing Q4 results")
```

#### Message Template
`"Decorative image '{imageName}' may need .accessibilityHidden(true) to avoid VoiceOver noise"`

#### Suggestion
`"Add .accessibilityHidden(true) if this image is decorative, or .accessibilityLabel() if it conveys meaningful information."`

#### Implementation Notes
- Opt-in because determining "decorative" from AST alone is heuristic. The rule should be conservative and focus on high-confidence cases (`.background()`, low opacity, naming patterns).
- This complements `iconOnlyButtonMissingLabel` which covers the interactive case. This covers the non-interactive case.

---

## Architecture

### god-view-model

**Rule Identifier:** `godViewModel`
**Category:** `.architecture`
**Severity:** `.warning`
**Opt-in:** No
**SwiftLint overlap:** None. `type_body_length` counts lines, not `@Published` properties. SPL adds semantic property-count analysis specific to the MVVM pattern.

#### Problem

View models with many `@Published` properties become god objects — they manage too much state, are hard to test, and couple unrelated concerns. This is the MVVM equivalent of the `fatView` rule. When a view model exceeds 10 published properties, it's a strong signal that it should be split into focused sub-view-models.

#### Detection Logic

**Visitor type:** `SyntaxVisitor` overriding `visit(_ node: ClassDeclSyntax)`

1. Identify classes conforming to `ObservableObject`.
2. Count properties annotated with `@Published`.
3. If the count exceeds the threshold (default: 10), flag the class.
4. Also check classes annotated with `@Observable` and count `var` properties (all are implicitly observed).
5. For `@Observable` classes, use a higher threshold (default: 15) since the macro encourages more granular observation.

#### Examples

```swift
// FLAGGED: 12 @Published properties
class AppViewModel: ObservableObject {
    @Published var userName: String = ""
    @Published var email: String = ""
    @Published var isLoggedIn: Bool = false
    @Published var items: [Item] = []
    @Published var selectedItem: Item?
    @Published var isLoading: Bool = false
    @Published var errorMessage: String?
    @Published var searchText: String = ""
    @Published var filterOption: FilterOption = .all
    @Published var sortOrder: SortOrder = .dateDesc
    @Published var showSettings: Bool = false
    @Published var notificationCount: Int = 0
}
```

#### Message Template
`"'{className}' has {count} @Published properties — consider splitting into focused view models"`

#### Suggestion
`"Group related properties into separate ObservableObject classes (e.g., AuthViewModel, SearchViewModel) and compose them at the view level."`

#### Implementation Notes
- Threshold should be a static constant in the visitor (matching the pattern used by `TooManyEnvironmentObjectsVisitor`).
- The rule mirrors the logic of `fatView` (which counts `@State` properties) but for the MVVM layer.

---

### view-model-direct-db-access

**Rule Identifier:** `viewModelDirectDBAccess`
**Category:** `.architecture`
**Severity:** `.info`
**Opt-in:** Yes
**SwiftLint overlap:** None. No SwiftLint rule checks import statements for architectural layering violations.

#### Problem

View models that directly import and use persistence frameworks (`CoreData`, `SwiftData`, `GRDB`, `RealmSwift`, `SQLite`) violate the separation of concerns principle. Direct database access in view models makes them hard to test (requires database setup), hard to migrate (persistence framework changes ripple through all view models), and couples business logic to storage implementation.

#### Detection Logic

**Visitor type:** `SyntaxVisitor` with import tracking

1. Scan import declarations for persistence frameworks:
   - `CoreData`, `SwiftData`, `RealmSwift`, `GRDB`, `SQLite`
2. Check if the file also contains a class conforming to `ObservableObject` or annotated with `@Observable`.
3. If both conditions are met, flag the import.
4. Additionally detect direct usage patterns inside view model classes:
   - `NSManagedObjectContext`, `ModelContext`, `@Query`, `@FetchRequest`
   - `Realm()`, `try! Realm()`
   - `Database.queue`, `dbPool.read`, `dbPool.write`
5. **Suppress** if:
   - The file name suggests it IS a repository/service (e.g., contains `Repository`, `Store`, `Service`, `DataSource`, `DAO`).
   - The class name suggests it's a repository layer, not a view model.

#### Examples

```swift
// FLAGGED
import SwiftData

@Observable
class TaskListViewModel {
    var modelContext: ModelContext  // Direct persistence access

    func addTask(title: String) {
        let task = TaskItem(title: title)
        modelContext.insert(task)
    }
}

// OK: Uses a repository abstraction
class TaskListViewModel: ObservableObject {
    private let repository: TaskRepositoryProtocol

    func addTask(title: String) async throws {
        try await repository.create(title: title)
    }
}
```

#### Message Template
`"View model '{className}' directly imports '{framework}' — consider using a repository/service layer"`

#### Suggestion
`"Extract persistence logic into a repository or service class. This improves testability (mock the repository) and makes persistence framework changes localized."`

#### Implementation Notes
- Opt-in because this is an architectural opinion. Many small apps intentionally use `@Query` directly in views/view-models per Apple's SwiftData tutorials.
- The heuristic for "is this a view model" should check class names ending in `ViewModel`, `VM`, or classes conforming to `ObservableObject`/`@Observable`.

---

### circular-dependency

**Rule Identifier:** `circularDependency`
**Category:** `.architecture`
**Severity:** `.warning`
**Opt-in:** No
**SwiftLint overlap:** None. SwiftLint is single-file only; it cannot perform cross-file dependency graph analysis.

#### Problem

When type A holds a reference to type B and type B holds a reference to type A, you have a circular dependency. This creates tight coupling, makes both types impossible to test in isolation, and often indicates a missing abstraction (a protocol or mediator pattern). It can also cause retain cycles if both references are strong.

#### Detection Logic

**Visitor type:** `CrossFilePatternVisitorProtocol` (requires cross-file analysis)

1. For each file, build a map of: `TypeName → Set<ReferencedTypeNames>`.
   - Scan stored properties, function parameters, and generic constraints.
   - Only track types defined within the project (not Foundation/UIKit types).
2. In `finalizeAnalysis()`, build a directed graph from these maps.
3. Detect cycles of length 2 (A→B→A). Optionally detect length 3 (A→B→C→A) but these are less common and noisier.
4. Report one issue per cycle, attached to both files.
5. **Suppress** if:
   - One side of the reference is a `weak` property (breaks the retain cycle, though the architectural coupling remains).
   - One side references the other through a protocol (the dependency is inverted, which is the fix).
   - Parent-child relationships where the child has a `weak` reference back to the parent (common and intentional pattern, e.g., delegate).

#### Examples

```swift
// FLAGGED: Circular dependency
// File: UserManager.swift
class UserManager {
    var sessionManager: SessionManager  // References SessionManager
}

// File: SessionManager.swift
class SessionManager {
    var userManager: UserManager  // References UserManager back
}

// SUPPRESSED: Dependency inversion via protocol
class UserManager {
    var sessionProvider: SessionProviding  // Protocol, not concrete type
}

class SessionManager: SessionProviding {
    var userManager: UserManager
}
```

#### Message Template
`"Circular dependency detected: '{typeA}' ↔ '{typeB}'"`

#### Suggestion
`"Break the cycle by introducing a protocol for one side, using a mediator/coordinator pattern, or merging the types if they represent a single concern."`

#### Implementation Notes
- This is a cross-file analysis rule. Follow the pattern used by `CrossFileSwiftUIManagementVisitor`.
- Building the type reference graph requires resolving type names across files. Without full type checking, use simple name matching (if type `Foo` appears as a stored property type in the file defining `Bar`, record `Bar → Foo`).
- For the first version, limit to length-2 cycles. Longer cycles are rarer and the detection is more expensive.
- Use the multi-location `LintIssue` initializer to report both files involved in the cycle.

---

## Code Quality

### redundant-binding

> **SUPERSEDED — Do not implement.** SwiftLint's `shorthand_optional_binding` (opt-in) already detects `if let x = x` and auto-corrects to `if let x`. Enable that rule instead.

**Rule Identifier:** `redundantBinding`
**Category:** `.modernization`
**Severity:** `.info`
**Opt-in:** No
**SwiftLint overlap:** Full — `shorthand_optional_binding` (opt-in) provides identical detection with autocorrect support.

#### Problem

Swift 5.7 introduced shorthand optional binding: `if let x` instead of `if let x = x`. The old form is redundant when the binding name matches the unwrapped variable name. The shorthand is clearer and reduces noise.

#### Detection Logic

**Visitor type:** `SyntaxVisitor` overriding `visit(_ node: OptionalBindingConditionSyntax)`

1. Check if the binding has the form `let x = x` or `var x = x` where both identifiers are the same.
2. This includes `if let`, `guard let`, and `while let` contexts.
3. Flag the redundant `= x` part.
4. **Suppress** if:
   - The binding unwraps a different expression (e.g., `let x = self.x`, `let x = dict["x"]`).
   - The project's minimum deployment target is below Swift 5.7 / iOS 16 (would need configuration input).

#### Examples

```swift
// FLAGGED
if let name = name {
    print(name)
}

guard let value = value else { return }

// OK: Different expression
if let name = self.name { }
if let name = names.first { }

// OK (Swift 5.7+): Shorthand
if let name {
    print(name)
}
```

#### Message Template
`"Redundant optional binding — 'let {name} = {name}' can be simplified to 'let {name}'"`

#### Suggestion
`"Use the Swift 5.7 shorthand: 'if let {name}' instead of 'if let {name} = {name}'."`

#### Implementation Notes
- SwiftSyntax makes this straightforward: check if the `OptionalBindingConditionSyntax` has an initializer, and if the initializer's expression is a `DeclReferenceExprSyntax` with the same identifier as the pattern.
- This is a clean, low-false-positive rule. Good candidate for autocorrect in the future.

---

### string-switch-over-enum

**Rule Identifier:** `stringSwitchOverEnum`
**Category:** `.codeQuality`
**Severity:** `.info`
**Opt-in:** Yes
**SwiftLint overlap:** None. No SwiftLint rule detects switching on `.rawValue` instead of the enum directly.

#### Problem

When developers switch on `someEnum.rawValue` (a `String`) instead of switching on the enum itself, they lose exhaustiveness checking. If a new case is added to the enum, the string switch silently falls through to `default` instead of producing a compiler error. This defeats one of Swift's most valuable safety features.

#### Detection Logic

**Visitor type:** `SyntaxVisitor` overriding `visit(_ node: SwitchExprSyntax)`

1. Check if the switch subject is a member access ending in `.rawValue`.
2. Check if the switch cases use string literal patterns.
3. If both conditions are met, check whether the base type of `.rawValue` is a known enum in the project (use `knownEnumTypes` from `BasePatternVisitor`).
4. If it is (or heuristically likely), flag the switch.
5. Also flag patterns like `switch String(describing: someEnum)`.
6. **Suppress** if:
   - The raw value comes from external input (e.g., JSON decoding) where you don't have the enum value yet.
   - The switch is inside a `Codable` implementation (common pattern for custom decoding).

#### Examples

```swift
enum Status: String {
    case active, inactive, pending
}

// FLAGGED
switch status.rawValue {
case "active": handleActive()
case "inactive": handleInactive()
default: break  // Silently ignores new cases
}

// OK: Switch on the enum directly
switch status {
case .active: handleActive()
case .inactive: handleInactive()
case .pending: handlePending()
// Compiler error if new case added
}
```

#### Message Template
`"Switch on '.rawValue' loses exhaustiveness checking — switch on the enum directly"`

#### Suggestion
`"Switch on the enum value instead of its raw value to get compile-time exhaustiveness checking when new cases are added."`

#### Implementation Notes
- Opt-in because the heuristic for "is this an enum rawValue" without type info can produce false positives.
- Use `knownEnumTypes` (already populated by the cross-file pre-scan) to improve accuracy.

---

### nested-generic-complexity

**Rule Identifier:** `nestedGenericComplexity`
**Category:** `.codeQuality`
**Severity:** `.info`
**Opt-in:** Yes
**SwiftLint overlap:** Partial — `nesting` (default) checks type/function nesting depth, and `generic_type_name` (opt-in) checks naming conventions. Neither counts generic parameter arity or detects deeply nested signatures like `Result<Array<Optional<T>>, Error>`. SPL adds generic-specific complexity analysis.

#### Problem

Types or functions with many generic parameters (3+) become difficult to read, understand, and use correctly. Deeply nested generics like `Result<Array<Optional<MyType>>, Error>` harm readability. This is often a sign that a typealias or intermediate type would improve clarity.

#### Detection Logic

**Visitor type:** `SyntaxVisitor` overriding `visit(_ node: GenericParameterClauseSyntax)` and `visit(_ node: GenericArgumentClauseSyntax)`

1. For generic declarations (`func foo<A, B, C, D>(...)`): count the generic parameters. Flag if ≥ 4.
2. For generic arguments (`SomeType<A, B<C>, D>`): count the nesting depth. Flag if depth ≥ 3 (e.g., `Result<Array<Optional<T>>, Error>` has depth 3).
3. Also flag where clause complexity: `where` clauses with more than 3 constraints.
4. **Suppress** if:
   - The type is in a file with "Generic" or "Builder" in the name (generic utility code is expected to be generic-heavy).
   - The declaration is a protocol with associated types (generics are the mechanism, not a choice).

#### Examples

```swift
// FLAGGED: 4 generic parameters
func transform<Input, Output, Intermediate, Error>(
    _ input: Input,
    via: (Input) -> Intermediate,
    then: (Intermediate) -> Result<Output, Error>
) -> Output { }

// FLAGGED: 3 levels of nesting
var result: Result<Array<Optional<UserResponse>>, NetworkError>

// OK: 2 generic parameters
func map<Input, Output>(_ transform: (Input) -> Output) -> [Output]
```

#### Message Template
`"Generic complexity: {count} type parameters (or nesting depth {depth}) — consider using typealiases or intermediate types"`

#### Suggestion
`"Introduce typealiases to simplify complex generic signatures, or consider whether an intermediate wrapper type would improve readability."`

#### Implementation Notes
- Opt-in because generic-heavy code is sometimes necessary (especially in framework/library code).
- Threshold of 4 parameters and depth of 3 are starting points. The existing pattern of hardcoded thresholds in visitors applies here.

---

## Modernization

### legacy-string-format

**Rule Identifier:** `legacyStringFormat`
**Category:** `.modernization`
**Severity:** `.info`
**Opt-in:** No
**SwiftLint overlap:** None. No SwiftLint rule flags `String(format:)` in favor of string interpolation.

#### Problem

`String(format:)` with format specifiers (`%@`, `%d`, `%f`, etc.) is a C-era pattern that is type-unsafe, crash-prone (wrong specifier = runtime crash), and harder to read than Swift's native string interpolation. Most `String(format:)` calls can be replaced with interpolation.

#### Detection Logic

**Visitor type:** `SyntaxVisitor` overriding `visit(_ node: FunctionCallExprSyntax)`

1. Detect calls to `String(format:` or `NSString(format:`.
2. Check the format string for C-style specifiers: `%@`, `%d`, `%f`, `%ld`, `%lu`, `%s`, etc.
3. Flag the call.
4. **Suppress** if:
   - The format string uses positional specifiers (`%1$@`, `%2$d`) — these are used for localization reordering and don't have a simple interpolation equivalent.
   - The format string is a variable (likely a localized string key — `NSLocalizedString` + `String(format:)` is the standard pattern).
   - The call is `String(format: NSLocalizedString(...), ...)` (localization pattern).
   - The format uses `%02d` or other padding/precision specifiers that don't have trivial interpolation equivalents.

#### Examples

```swift
// FLAGGED
let message = String(format: "Hello %@, you have %d items", name, count)
let price = String(format: "Price: $%f", amount)

// OK (suppressed): Localization pattern
let msg = String(format: NSLocalizedString("greeting", comment: ""), name)

// OK (suppressed): Padding specifier
let time = String(format: "%02d:%02d", hours, minutes)

// PREFERRED: String interpolation
let message = "Hello \(name), you have \(count) items"
let price = "Price: $\(amount)"
```

#### Message Template
`"String(format:) with C-style specifiers — consider using string interpolation"`

#### Suggestion
`"Replace with Swift string interpolation for type safety and readability. Use formatted() for number/date formatting."`

#### Implementation Notes
- The localization suppression is critical — `String(format: NSLocalizedString(...))` is the correct pattern and should never be flagged.
- Regex for format specifiers: `%[0-9]*\.?[0-9]*[dDiIuUxXoObBfFeEgGaAcCsSpP@]`

---

### legacy-array-init

**Rule Identifier:** `legacyArrayInit`
**Category:** `.modernization`
**Severity:** `.info`
**Opt-in:** Yes
**SwiftLint overlap:** Partial — `syntactic_sugar` (default) flags `Array<T>` in type annotations and suggests `[T]`. However, it targets type declarations only, not initializer call expressions like `Array<T>()` → `[T]()`. SPL would target the initializer call pattern specifically.

#### Problem

`Array<Element>()`, `Dictionary<Key, Value>()`, `Set<Element>()`, and `Optional<Wrapped>.none` can be written more concisely using Swift's sugar syntax: `[Element]()`, `[Key: Value]()`, `Set<Element>()`, and `nil`. While functionally identical, the verbose forms are non-idiomatic.

#### Detection Logic

**Visitor type:** `SyntaxVisitor` overriding `visit(_ node: FunctionCallExprSyntax)`

1. Detect initializer calls to `Array<...>()`, `Dictionary<...>()`.
2. Only flag when the generic argument is explicitly provided and the initializer takes no arguments (empty collection).
3. `Set` is excluded since `Set<Element>()` is already the shortest form.
4. Also detect `Optional<T>.none` vs `nil` and `Optional<T>.some(x)` vs `x`.
5. **Suppress** if the generic form is used for disambiguation (rare, but possible in overloaded contexts).

#### Examples

```swift
// FLAGGED
let items: Array<String> = Array<String>()
let map = Dictionary<String, Int>()
let nothing: Optional<String> = Optional<String>.none

// PREFERRED
let items: [String] = []
let map: [String: Int] = [:]
let nothing: String? = nil
```

#### Message Template
`"'{verboseForm}' can be simplified to '{shortForm}'"`

#### Suggestion
`"Use Swift's shorthand syntax: [Element]() for Array, [Key: Value]() for Dictionary, nil for Optional.none."`

#### Implementation Notes
- Opt-in because this is a pure style preference and the verbose form is not incorrect.
- Good candidate for autocorrect.

---

### legacy-closure-syntax

**Rule Identifier:** `legacyClosureSyntax`
**Category:** `.modernization`
**Severity:** `.info`
**Opt-in:** Yes
**SwiftLint overlap:** Partial — `trailing_closure` and `unneeded_parentheses_in_closure_argument` (both opt-in) address specific closure style issues. Neither flags redundant type annotations on closure parameters where types are inferrable from context. SPL adds inference-aware type annotation detection.

#### Problem

Explicitly typing closure parameters when the types can be inferred adds noise without improving clarity. Swift's type inference handles closure parameter types in most contexts.

#### Detection Logic

**Visitor type:** `SyntaxVisitor` overriding `visit(_ node: ClosureExprSyntax)`

1. Check the closure's parameter clause for explicit type annotations.
2. Determine if the closure is in a context where types are inferrable:
   - Passed as an argument to a function with a known closure type.
   - Assigned to a variable with an explicit closure type annotation.
   - Used with `.map`, `.filter`, `.reduce`, `.compactMap`, `.sorted`, etc.
3. Flag closures with redundant type annotations in these contexts.
4. **Suppress** if:
   - The closure is a top-level closure assigned to an untyped variable (types needed).
   - The closure has complex overload resolution (removing types would be ambiguous).
   - The closure body exceeds 10 lines (explicit types aid readability in long closures).

#### Examples

```swift
// FLAGGED: Types are inferrable from .map context
let names = users.map { (user: User) -> String in
    return user.name
}

// PREFERRED
let names = users.map { user in user.name }
// or
let names = users.map(\.name)

// SUPPRESSED: Long closure where types aid readability
let processed = items.reduce(into: [:]) { (result: inout [String: Int], item: Item) in
    // ... 15 lines of processing
}
```

#### Message Template
`"Closure parameter types can be inferred — explicit type annotations are redundant"`

#### Suggestion
`"Remove the explicit type annotations and let Swift infer them from context. Use '$0' shorthand for single-expression closures."`

#### Implementation Notes
- Opt-in because some teams prefer explicit closure types for documentation purposes.
- This is difficult to implement perfectly without type checking. Focus on high-confidence cases: standard library higher-order functions, Combine operators, and closures passed to methods with unambiguous signatures.

---

### ios17-observation-migration

**Rule Identifier:** `ios17ObservationMigration`
**Category:** `.modernization`
**Severity:** `.info`
**Opt-in:** Yes
**SwiftLint overlap:** None. No SwiftLint rule suggests migrating `ObservableObject` to `@Observable` or assesses migration readiness.

#### Problem

The `@Observable` macro (iOS 17+) replaces the `ObservableObject` protocol + `@Published` pattern with a simpler, more performant model. Views using `@Observable` objects get more granular update tracking (only re-render when actually-read properties change, not when any `@Published` property changes). This is a significant performance improvement for complex view hierarchies.

Note: The existing `legacyObservableObject` rule already flags this. This proposal is for a more nuanced companion rule.

#### Detection Logic

**Visitor type:** `SyntaxVisitor` overriding `visit(_ node: ClassDeclSyntax)`

1. Identify classes conforming to `ObservableObject`.
2. Count `@Published` properties vs. non-published stored properties.
3. Report migration candidates with a readiness score:
   - **High readiness**: Class only uses `@Published`, no `objectWillChange.send()` calls, no `@ObservedObject` wrapper usage.
   - **Medium readiness**: Uses `objectWillChange.send()` manually (need to remove those calls).
   - **Low readiness**: Relies on `ObservableObject` protocol features like `objectWillChange` publisher being Combine-compatible.
4. Flag with readiness context so developers can prioritize.
5. **Suppress** if:
   - The class is in a module that needs to support iOS < 17.
   - The class subclasses an `NSObject` (can't use `@Observable` macro).
   - The class uses `objectWillChange` as a Combine publisher downstream.

#### Examples

```swift
// FLAGGED (high readiness)
class ProfileViewModel: ObservableObject {
    @Published var name: String = ""
    @Published var avatar: Image?
}
// Suggested migration:
// @Observable
// class ProfileViewModel {
//     var name: String = ""
//     var avatar: Image?
// }

// FLAGGED (medium readiness) — manual objectWillChange
class CounterViewModel: ObservableObject {
    @Published var count: Int = 0

    func increment() {
        objectWillChange.send()
        count += 1
    }
}

// SUPPRESSED: Uses Combine publisher features
class StreamViewModel: ObservableObject {
    @Published var items: [Item] = []

    var cancellable: AnyCancellable?

    init() {
        cancellable = $items
            .debounce(for: .seconds(1), scheduler: RunLoop.main)
            .sink { /* ... */ }
    }
}
```

#### Message Template
`"'{className}' could migrate to @Observable (readiness: {readiness}) — improved performance with granular tracking"`

#### Suggestion
`"Replace 'ObservableObject' conformance with '@Observable' macro, remove '@Published' wrappers, and update '@ObservedObject' to plain properties in views."`

#### Implementation Notes
- This is a more detailed companion to the existing `legacyObservableObject` rule. Consider whether to enhance that rule or create this as a separate opt-in rule.
- The readiness scoring gives actionable prioritization rather than just flagging everything.
- The Combine publisher usage detection (suppress case) is important — `@Observable` doesn't provide `$property` publishers.

---

## Modifications to Existing Rules

---

### hardcoded-secret (expand)

**Current rule:** Detects hardcoded secrets, passwords, API keys, and tokens in source code.
**SwiftLint overlap:** None. SwiftLint has no hardcoded secret detection at all.

#### Proposed Modifications

1. **JWT detection**: Add regex for JSON Web Tokens: `eyJ[A-Za-z0-9-_]+\.eyJ[A-Za-z0-9-_]+\.[A-Za-z0-9-_]+`. JWTs always start with `eyJ` (base64 of `{"`) and have three dot-separated segments.

2. **Base64-encoded secrets**: Detect long base64 strings (40+ chars matching `[A-Za-z0-9+/=]+`) assigned to variables with sensitive names. Don't flag all base64 strings (too many false positives) — only when the variable name suggests it's a secret.

3. **Plist-style key-value patterns**: Detect string assignments where the key/variable contains sensitive terms and the value looks like a secret (high entropy, 20+ characters, mixed case/digits). Example:
   ```swift
   let APIKey = "sk-1234567890abcdef1234567890abcdef"
   ```

4. **Common API key prefixes**: Detect known service key prefixes:
   - `sk-` (OpenAI, Stripe secret keys)
   - `pk_` / `sk_` (Stripe)
   - `ghp_` / `gho_` / `ghs_` (GitHub tokens)
   - `xoxb-` / `xoxp-` (Slack tokens)
   - `AKIA` (AWS access keys)
   - `AIza` (Google API keys)
   - `SG.` (SendGrid)

5. **Entropy heuristic**: For string literals assigned to sensitive-named variables, compute Shannon entropy. Secrets typically have entropy > 4.0 bits per character. This catches randomly generated keys that don't match known prefixes.

#### Suppression Updates
- Continue to suppress strings inside `#if DEBUG` blocks.
- Suppress known placeholder values: `"YOUR_API_KEY_HERE"`, `"REPLACE_ME"`, `"TODO"`.
- Suppress strings in test files that are clearly mock values.

---

### magic-number (add boolean sub-rule)

**Current rule:** Detects hardcoded numbers that should be named constants.
**SwiftLint overlap:** Partial — `no_magic_numbers` (opt-in) covers numeric literals only. It does not detect "magic boolean parameters" (e.g., `configure(true, false, true)`). SPL adds boolean parameter smell detection.

#### Proposed Modification

Add a companion sub-rule (or new rule `magicBooleanParameter`) that detects boolean literal arguments in function calls without argument labels:

```swift
// FLAGGED: What do true and false mean here?
configureView(true, false, true)
process(data, true)

// OK: Labeled
configureView(animated: true, recursive: false, verbose: true)
```

#### Detection Logic

1. Detect function calls with 2+ boolean literal arguments, or function calls where a boolean literal is passed without an argument label.
2. **Suppress** for well-known APIs where unlabeled booleans are standard: `XCTAssertEqual`, `#expect`, `print`, `UIView.animate(withDuration:animations:)`, etc.
3. **Suppress** when the function is defined in the same project and the parameter has a descriptive name (the label was intentionally omitted with `_`).

#### Severity
`.info` — this is a readability suggestion, not a bug.

#### Implementation Notes
- This could be a separate rule (`magicBooleanParameter`) rather than modifying `magicNumber`, since the detection logic is different (function call arguments vs. numeric literals).
- Category: `.codeQuality`

---

### law-of-demeter (SwiftUI exemptions)

**Current rule:** Flags member access chains 3+ levels deep.
**SwiftLint overlap:** None. SwiftLint has no Law of Demeter rule.

#### Proposed Modification

Add exemptions for idiomatic SwiftUI and Swift patterns that naturally involve deep access chains:

1. **Environment keypath access**: `\.colorScheme`, `environment.settings.theme` — environment objects naturally form hierarchies.
2. **Binding projections**: `$viewModel.settings.name` — bindings chain through published properties.
3. **KeyPath expressions**: `\SomeType.property.nested` — keypath literals are declarative, not "reaching through" objects.
4. **Builder/fluent patterns**: `.font(.system(size:weight:design:))` — SwiftUI modifiers chain intentionally.
5. **NavigationPath/NavigationStack**: Navigation code naturally chains.

#### Detection Logic Updates

Add a set of exemption patterns checked before flagging:

```
// These patterns should NOT be flagged:
$viewModel.user.name          // Binding projection (starts with $)
\.user.name                   // KeyPath literal (starts with \)
environment.theme.color       // Starts with 'environment' (case-insensitive)
Color.blue.opacity(0.5)      // Chaining on a static member + modifier
view.frame.size.width         // Geometry patterns (frame/size/bounds/origin)
```

#### Implementation Notes
- The exemption list should be a static set in the visitor, easy to extend.
- Consider making the threshold configurable (some teams are fine with 4 levels).

---

### single-implementation-protocol (test-aware)

**Current rule:** Flags protocols that have only one conforming type, suggesting unnecessary abstraction.
**SwiftLint overlap:** None. SwiftLint has no rule for protocols with only one conformer.

#### Proposed Modification

Make the rule aware of test targets. A protocol with one production conformer but one or more test/mock conformers is *not* unnecessary — it's the dependency injection + mocking pattern, which is good architecture.

#### Detection Logic Updates

1. In the cross-file analysis, when counting conformers, also scan files in paths matching `/Tests/`, `/XCTests/`, `/Mocks/`, `/Fakes/`, `/Stubs/`.
2. If the protocol has 1 production conformer + 1 or more test conformers, **suppress**.
3. If the protocol has 1 production conformer + 0 test conformers, flag as current.

#### Additional Heuristic

Also suppress if the protocol name ends with common mockable suffixes:
- `Protocol`, `Providing`, `Service`, `Repository`, `DataSource`, `Client`, `Networking`

These names strongly imply the protocol exists for dependency injection even if no mock conformer exists yet.

---

### print-statement (debug-aware)

**Current rule:** Flags all `print()` and `debugPrint()` calls with `.info` severity.
**SwiftLint overlap:** None. SwiftLint has no built-in print statement rule (feature request [#2484](https://github.com/realm/SwiftLint/issues/2484) was never implemented).

#### Proposed Modification

Add context-awareness for debug-only code:

1. **Suppress** `print()` calls inside `#if DEBUG` blocks — these are intentionally development-only and are compiled out in release builds.
2. **Tiered severity**:
   - `.info` for `print()` inside `#if DEBUG` (suppress entirely, or keep as `.info` with a different message).
   - `.warning` for `print()` in production code paths — this is more actionable.
3. **Detect** `debugPrint()` outside `#if DEBUG` with higher severity — `debugPrint` is explicitly a debug tool, finding it in production paths is a stronger signal.

#### Message Updates

```
// In #if DEBUG → suppressed or info:
"print() in #if DEBUG block — will be compiled out in release"

// Outside #if DEBUG → warning:
"print() statement in production code — use os.Logger for structured logging"

// debugPrint outside DEBUG → warning:
"debugPrint() outside #if DEBUG — likely left over from debugging"
```

---

### missing-preview (tiered severity)

**Current rule:** Flags SwiftUI views missing `#Preview` or `PreviewProvider` with uniform severity.
**SwiftLint overlap:** None. No SwiftLint rule checks for SwiftUI `#Preview` / `PreviewProvider`.

#### Proposed Modification

Tier the severity based on the view's access level and complexity:

1. **`.warning`** for `public` or `open` views — these are part of a module's API and previews serve as living documentation.
2. **`.info`** for `internal` views with 5+ properties or complex `body` — these benefit from previews but it's less critical.
3. **Suppress** for:
   - `private` or `fileprivate` views (small helper views extracted for readability).
   - Views with fewer than 3 lines in `body` (trivial wrapper views).
   - Views in files matching `*+Extensions.swift` or `*Helper.swift`.

#### Detection Logic Updates

1. Check the view's access level modifier.
2. Count the lines in the `body` property.
3. Check if a `#Preview` block or `PreviewProvider` conformance exists in the same file.
4. Apply tiered severity based on the above.

---

### for-each-self-id (expand to hashValue)

**Current rule:** Flags `ForEach` using `.self` as the ID.
**SwiftLint overlap:** None. No SwiftLint rule checks `ForEach` identity patterns.

#### Proposed Modification

Also flag `\.hashValue` as an ID keypath:

```swift
// Currently flagged
ForEach(items, id: \.self) { item in ... }

// Should also be flagged
ForEach(items, id: \.hashValue) { item in ... }
```

#### Why

`hashValue` is not guaranteed to be unique — hash collisions are expected and normal. Using it as an identity causes SwiftUI to confuse items with the same hash, leading to:
- Wrong items being updated/animated.
- Items disappearing or duplicating.
- Subtle, hard-to-reproduce bugs.

#### Detection Logic Updates

Add `\.hashValue` to the set of flagged ID keypaths alongside `\.self`. The message should explain that `hashValue` is not unique:

```
"ForEach using \.hashValue as ID — hash values are not unique and will cause incorrect view updates"
```

#### Suggestion
`"Use a stable, unique identifier like \.id. Conform the element to Identifiable if possible."`

---

## Priority Recommendations

### Highest Impact (implement first)
1. **formatter-in-view-body** — Catches one of the most common SwiftUI performance mistakes; no SwiftLint equivalent
2. **main-actor-missing-on-ui-code** — Catches the most common SwiftUI concurrency crash; no SwiftLint equivalent
3. **user-defaults-sensitive-data** — Catches a genuine security vulnerability; no SwiftLint equivalent
4. **unchecked-sendable** — Critical for Swift 6 migration; no SwiftLint equivalent
5. **for-each-self-id expansion** — Trivial change to existing rule, catches real bugs; no SwiftLint equivalent

### High Impact
6. **insecure-transport** — Easy to implement, clear value; no SwiftLint equivalent
7. **god-view-model** — Natural extension of existing `fatView` rule; no SwiftLint equivalent
8. **tap-target-too-small** — Measurable accessibility improvement; no SwiftLint equivalent
9. **image-without-resizable** — Common beginner mistake; no SwiftLint equivalent
10. **hardcoded-secret expansion** — JWT, base64, API key prefix detection; no SwiftLint equivalent

### Medium Impact (implement when capacity allows)
11. **logging-sensitive-data** — Useful but higher false-positive potential; no SwiftLint equivalent
12. **circular-dependency** — Valuable but complex cross-file analysis; no SwiftLint equivalent
13. **unbounded-task-group** — Niche but high-severity when applicable; no SwiftLint equivalent
14. **print-statement modification** — Reduces noise from current rule; no SwiftLint equivalent
15. **law-of-demeter modification** — Reduces false positives; no SwiftLint equivalent

### Lower Priority (opt-in, nice-to-have)
16. **ios17-observation-migration** — Overlaps with existing rule; no SwiftLint equivalent
17. **legacy-string-format** — Style preference; no SwiftLint equivalent
18. **string-switch-over-enum** — Hard without type info; no SwiftLint equivalent
19. **nested-generic-complexity** — Style preference; partial SwiftLint overlap (`nesting` + `generic_type_name`)
20. **legacy-closure-syntax** — Very hard to implement correctly without type info; partial SwiftLint overlap (`trailing_closure`)

### Superseded (do not implement)
- ~~**redundant-binding**~~ — Fully covered by SwiftLint's `shorthand_optional_binding` (opt-in). Enable that rule instead.
