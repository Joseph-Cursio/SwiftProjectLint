[← Back to Rules](RULES.md)

## Disfavored Overload

**Identifier:** `Disfavored Overload`
**Category:** Code Quality
**Severity:** Warning

### Rationale

`@_disfavoredOverload` is a compiler-internal attribute. The leading underscore is Swift's explicit convention for "not part of the public language — no stability guarantees." Code that relies on this attribute is coupling itself to compiler internals that may change behavior or disappear between Swift versions without notice.

### Discussion

`DisfavoredOverloadVisitor` detects `@_disfavoredOverload` on `FunctionDeclSyntax` and `InitializerDeclSyntax` nodes anywhere in non-generated source. The detection is binary — there is no edge case where the attribute is acceptable in production code.

**Legitimate intent, wrong tool:**

```swift
// Before — using @_disfavoredOverload to bias overload resolution
@_disfavoredOverload
func process<T>(_ value: T) { ... }  // generic fallback

func process(_ value: String) { ... }  // preferred for strings
```

The right fix is to redesign the overload set so the compiler selects the correct overload without the crutch, or to differentiate the functions with distinct names.

```swift
// After — distinct names make intent explicit
func processString(_ value: String) { ... }
func processGeneric<T>(_ value: T) { ... }
```

### Non-Violating Examples

```swift
// No attribute — overload resolution works without it
func process(_ value: String) -> String { value }
func process<T: Encodable>(_ value: T) throws -> Data { ... }

// Other attributes are fine
@discardableResult
func build() -> Self { self }
```

### Violating Examples

```swift
// @_disfavoredOverload in production code
@_disfavoredOverload
func process<T>(_ value: T) {}

struct Builder {
    @_disfavoredOverload
    init<T: Configurable>(_ config: T) { ... }
}
```

---
