[← Back to Rules](RULES.md)

## Discardable Result Misuse

**Identifier:** `Discardable Result Misuse`
**Category:** Code Quality
**Severity:** Info *(heuristic — false positives expected)*

### Rationale

`@discardableResult` silences the "result of call to X is unused" compiler warning. It is legitimate on builder and append-style functions where chaining is optional. It is misused when applied to suppress the warning on functions whose return value carries important outcome information — errors, validation results, success flags — turning the compiler's safety net into a silent footgun.

### Discussion

`DiscardableResultMisuseVisitor` applies two independent heuristic signals. Either is sufficient to flag:

**Signal 1 — Return type:**
- `Result<_, _>` — explicit error-carrying type
- Type name ending in `Result`, `Response`, `Status`, or `Outcome`

**Signal 2 — Function name:**
Name contains: `validate`, `save`, `submit`, `authenticate`, `authorize`, `verify`, `check`, `create`, `delete`, `update`, `send`, `upload`, `download`, `login`, `logout`, `register`, `commit`, `rollback`, `execute`, `apply`.

```swift
// Before — callers can silently ignore a failure case
@discardableResult
func save() throws -> Result<SaveRecord, SaveError> { ... }

// After — callers must handle the result or explicitly discard
func save() throws -> Result<SaveRecord, SaveError> { ... }
// Call site: _ = try save()  or  let result = try save()
```

### Legitimate Uses (Not Flagged)

```swift
// Builder / chaining style — result is optional
@discardableResult
func font(_ font: Font) -> Text { ... }

@discardableResult
func appending(_ element: Element) -> Self { ... }
```

### Violating Examples

```swift
// Result return type
@discardableResult
func authenticate() -> Result<User, AuthError> { ... }

// Type name with meaningful suffix
@discardableResult
func validate(_ input: String) -> ValidationResult { ... }

// Bool + suspicious name
@discardableResult
func saveRecord() -> Bool { ... }

// Suspicious name alone
@discardableResult
func submitOrder() -> OrderID { ... }
```

### Suppression

This rule uses name and type heuristics and will have false positives. Suppress with an inline comment when the annotation is intentional:

```swift
// swiftprojectlint:disable discardable-result-misuse
@discardableResult
func checkConnection() -> Bool { ... }
```

---
