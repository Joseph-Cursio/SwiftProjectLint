[← Back to Rules](RULES.md)

## Primitive Bypassing Its Domain Type

**Identifier:** `Primitive Bypassing Its Domain Type`
**Category:** Architecture
**Severity:** Info *(opt-in)*

### Rationale
"Primitive obsession" — modeling a domain concept (a dedup key, a user id, a currency amount)
as a bare `String`/`Int`/`UUID` that any value can impersonate — is a real smell, but it is
**not detectable by a linter**: whether a given `String` "is really an idempotency key" is
domain knowledge that lives in the developer's head, not in the syntax. This rule does not try
to detect it.

Instead it *polices the cure*. The moment a project declares a newtype `W` over a primitive `P`
(`struct IdempotencyKey { let value: String }`) and uses it to key a map, a **same-shaped map
still keyed by the raw `P`** becomes a visible, decidable inconsistency — the domain identity is
enforced in one place and laundered back to a bare primitive in another. Detecting the disease
is undecidable; policing the cure is merely a cross-file check. This is the design recorded in
[`Docs/primitive-bypassing-domain-type-rule-design.md`](../primitive-bypassing-domain-type-rule-design.md),
Variant A.

### Discussion
`PrimitiveBypassingDomainTypeVisitor` runs cross-file, in two phases.

1. **Collect.** Record every project **struct newtype** — a struct with exactly one stored
   instance property whose type is a bare primitive — as `wrapperName → carrier`. Record every
   `Dictionary` usage (`[K: V]` and `Dictionary<K, V>`) as a `(keyType, valueType)` pair.
2. **Match and emit.** For each carrier `P` that has a wrapper `W` used as a `[W: V]` key, flag
   every `[P: V]` usage keyed by the **raw carrier** to the **same value type** `V`, naming the
   wrapper it should use.

#### The matching value type is the false-positive guard
`String` keys thousands of unrelated dictionaries; flagging every `[String: X]` merely because
*some* `String` newtype exists would drown in noise. The rule fires only when a raw `[String: V]`
shares its value type `V` with an existing `[IdempotencyKey: V]` — the identical value type is
the evidence the two maps model one mapping, not a coincidence of the same key primitive. This
is the same discipline as [Shared Domain-Enum Field](shared-domain-enum-field.md)'s
project-enum requirement: a strong structural signal in place of a name guess.

#### Complements, does not overlap
[Shared Domain-Enum Field](shared-domain-enum-field.md) and
[Duplicate Struct Shape](duplicate-struct-shape.md) say *"a type is missing — create it."* This
rule says *"the type exists — use it."* Together they cover both halves of the modeling loop.
[Magic Number](magic-number.md) is the degenerate case — a raw literal with no wrapper at all.

#### Known limitations (v1)
- **Structs only.** Enums with raw types (`enum Currency: String`) and `RawRepresentable`
  conformances declared via `typealias RawValue` are not yet recognized as wrappers.
- **Dictionaries only.** `Set<P>` next to `Set<W>` is a weaker signal (no value type to match
  on) and is left out; deferred to a later variant.
- **Value-type match is textual.** Two maps whose value types are both a common type (`Bool`,
  `Int`) can match coincidentally; the rule is `Info` and opt-in for exactly this residue.
- Suppress a deliberate raw keying with `// swiftprojectlint:disable Primitive Bypassing Its Domain Type`.

### Non-Violating Examples
```swift
// No wrapper is used as a key — nothing to be consistent with. (Detecting that String
// *should* become a domain type is the undecidable half this rule does not attempt.)
struct IdempotencyKey { let value: String }
var responses: [String: Response] = [:]
```

```swift
// Consistent: both maps key by the domain type.
struct IdempotencyKey { let value: String }
var seen: [IdempotencyKey: Response] = [:]
var pending: [IdempotencyKey: Response] = [:]
```

```swift
// Same raw key, but no matching value type keyed by the wrapper — not the same mapping.
struct IdempotencyKey { let value: String }
var seen: [IdempotencyKey: Response] = [:]
var featureFlags: [String: Bool] = [:]      // different value type; ignored
```

### Violating Examples
```swift
// A newtype over String keys one map; a sibling map to the same value type is still keyed by
// the raw String — the bare key bypasses the domain type that already exists.
struct IdempotencyKey { let value: String }

var seen: [IdempotencyKey: Response] = [:]   // enforces the identity
var replayCache: [String: Response] = [:]    // ← flagged: bypasses IdempotencyKey
```

**Suggestion:** Key `replayCache` by `IdempotencyKey` too, so the dedup identity is enforced by
the type rather than a bare `String` any value can impersonate.

---
