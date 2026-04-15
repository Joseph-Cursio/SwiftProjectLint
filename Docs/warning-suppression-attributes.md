# Warning-Suppression Attributes as Lint Targets

Swift provides several attributes that suppress compiler warnings or opt out of compiler verification. Each is legitimate in specific circumstances, and each is commonly misused as a shortcut to silence warnings without addressing the underlying issue. These are high-value lint targets for the same reason `@unchecked Sendable` and `nonisolated(unsafe)` already are.

---

## `@discardableResult`

**What it does:** Suppresses the "result of call to X is unused" warning on the call site of a function that returns a value.

**Legitimate use:** Functions where the return value is genuinely optional for the caller — `append`-style operations, fire-and-forget logging, builder methods where chaining is optional.

```swift
@discardableResult
func append(_ element: Element) -> Self { ... }  // chaining optional
```

**The misuse pattern:** Applied to fix a warning on a function whose return value *should* be checked — errors, validation results, created objects.

```swift
@discardableResult
func save() throws -> SaveResult { ... }
// Now callers can silently ignore SaveResult — including failure cases
```

**What a lint rule would flag:** `@discardableResult` on functions whose return type is an error-carrying type (`Result`, `Error`, a type with an obvious success/failure semantic) or whose name implies a meaningful outcome (`validate`, `save`, `submit`, `authenticate`). The annotation is suppressing a warning the compiler is right to emit.

---

## `@preconcurrency`

**What it does:** Applied to an `import` or a protocol conformance, it softens Swift 6 concurrency errors back to warnings for APIs that predate Swift concurrency and haven't been annotated yet.

**Legitimate use:** Importing a third-party library that hasn't adopted `Sendable` annotations yet. The warnings are legitimate but outside your control.

```swift
@preconcurrency import SomeLegacySDK
```

**The misuse pattern:** Applied to your *own* modules or conformances to silence concurrency errors you should be fixing.

```swift
// Your own protocol, in your own module
@preconcurrency
extension MyViewModel: SomeProtocol { ... }
// This suppresses isolation errors that indicate a real design problem
```

**What a lint rule would flag:** `@preconcurrency` applied to conformances involving types defined in the same module. If it's your code, the right fix is adding proper concurrency annotations, not grandfathering it in.

---

## `@retroactive`

**What it does:** Marks a conformance where you're making a type you don't own (from module A) conform to a protocol you don't own (from module B). Swift 5.7+ warns about this because two separate libraries could define the same conformance, causing a conflict.

**Legitimate use:** Intentionally bridging two libraries you depend on, fully aware of the risk, in a controlled way.

```swift
extension URLComponents: @retroactive Identifiable {
    public var id: String { url?.absoluteString ?? "" }
}
```

**The misuse pattern:** Applied reflexively to silence the warning without understanding why the warning exists. The underlying risk — two modules defining conflicting conformances for the same type — is real and can cause subtle runtime behavior depending on which conformance the linker selects.

**What a lint rule would flag:** `@retroactive` where both the type and the protocol are from the Swift standard library or Foundation — these are the highest-risk cases because many libraries may define the same conformance independently.

---

## `@_disfavoredOverload`

**What it does:** A leading underscore signals this is an unofficial/internal compiler attribute. It hints to the compiler to prefer other overloads over this one during overload resolution when both are equally applicable.

**Legitimate use:** Providing a fallback overload that should only be selected when nothing more specific matches — common in generic library design.

```swift
@_disfavoredOverload
func process<T>(_ value: T) { ... }  // generic fallback

func process(_ value: String) { ... }  // preferred for strings
```

**The misuse pattern:** The leading underscore convention in Swift means "internal compiler use, no stability guarantees." Shipping code that depends on `@_disfavoredOverload` couples you to compiler internals that may change behavior between Swift versions without notice.

**What a lint rule would flag:** Any use of `@_disfavoredOverload` in non-test, non-generated source. If the overload resolution is wrong without it, the overload set should be redesigned rather than patched with an unstable attribute.

---

## Common Thread

All four follow the same pattern as `@unchecked Sendable` and `nonisolated(unsafe)`: they exist to handle cases the compiler can't fully verify, and they're frequently cargo-culted to make warnings disappear. The lint rules for these don't need to *ban* the attributes — they need to flag the specific misuse signatures:

| Attribute | Flag when... |
|---|---|
| `@discardableResult` | Return type has an error-carrying or meaningful-outcome semantic |
| `@preconcurrency` | Applied to conformances in the same module |
| `@retroactive` | Both type and protocol are from stdlib or Foundation |
| `@_disfavoredOverload` | Used anywhere in production code |

The value isn't catching every use — it's surfacing the cases where the attribute is doing the wrong job.

---

## Detection Strategy

How precisely the linter can identify misuse varies significantly between the four.

### `@discardableResult` — most detectable

The return type is visible in the AST. Flag it against a set of known error-carrying or meaningful-outcome types:

```swift
// Flag these return types under @discardableResult:
Result<_, _>
Bool          // when function name matches /validate|check|verify|save|submit/
Error         // (rare as return type but possible)
// ...and custom types whose name ends in Result, Response, Status, Outcome
```

The function name is also a strong signal. `@discardableResult func save()` is suspicious. `@discardableResult func appending()` is not.

This one has reasonable precision.

### `@preconcurrency` — also fairly detectable

The attribute has two forms: on an `import` and on a conformance. The rule only cares about the conformance form. Check whether the type being extended is defined in the same module — if it is, `@preconcurrency` is suppressing errors you own.

The hard part is "defined in the same module" requires knowing module boundaries, which means cross-file analysis. For single-target apps this is straightforward; for multi-package setups it's harder.

### `@retroactive` — the most mechanically reliable

The condition is precise: both the type and the protocol must be from modules you don't own. Check the import list — if neither the type's module nor the protocol's module appears as a local package, it's third-party. The highest-risk subset (both from stdlib/Foundation) is easy to check by name: `Swift`, `Foundation`, `SwiftUI`, `UIKit`, `AppKit`.

This is the most false-positive-free of the four.

### `@_disfavoredOverload` — trivial detection, binary rule

Flag every occurrence in non-generated source. There's no nuance to assess — if it's in production code, it's worth surfacing. The leading underscore convention is the signal; no semantic analysis needed.

---

## Detection Confidence and Suggested Severities

Three of the four require contextual judgment that static analysis approximates but can't fully make:

- Is this return type "meaningful enough" that ignoring it is dangerous?
- Is this conformance in a module you own?
- Is this third-party type well-known enough that retroactive conformance is risky?

The detection strategies above work on *structural signals* — names, types, module membership — as proxies for intent. They will have false positives. The question for each rule is whether the false positive rate is low enough that the signal is worth the noise.

| Attribute | Confidence | Suggested severity |
|---|---|---|
| `@_disfavoredOverload` | High — binary, no edge cases | Warning |
| `@retroactive` (stdlib/Foundation subset) | High — type names are unambiguous | Warning |
| `@preconcurrency` on conformances | Medium — requires module boundary analysis | Warning |
| `@discardableResult` | Medium — name/type heuristics have false positives | Info |

`@_disfavoredOverload` and `@retroactive` (stdlib/Foundation subset) are probably clean enough to ship as warnings. `@discardableResult` and `@preconcurrency` need more conservative heuristics — probably info-level suggestions until the signal quality is validated against real codebases.

---

*Document prepared April 2026.*
