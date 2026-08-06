[← Back to Rules](RULES.md)

## Primitive Named For Its Domain Type

**Identifier:** `Primitive Named For Its Domain Type`
**Category:** Architecture
**Severity:** Info *(opt-in)*

### Rationale
The name-correspondence sibling of
[Primitive Bypassing Its Domain Type](primitive-bypassing-its-domain-type.md). Where that rule
uses the structural inconsistent-keying signal, this one uses the *name*: a parameter or
property typed as a raw primitive `P` whose identifier matches a project newtype `W` over `P`.
A parameter `idempotencyKey: String` in a codebase that declares
`struct IdempotencyKey { let value: String }` names the domain type and then bypasses it — the
developer clearly means the concept but wrote the raw carrier.

Like its sibling, this rule does not attempt to *detect* primitive obsession (undecidable — the
domain rule is not in the syntax). It enforces an *already-declared* wrapper wherever a name
gives the concept away. See
[`Docs/design/primitive-bypassing-domain-type-rule-design.md`](../design/primitive-bypassing-domain-type-rule-design.md),
Variant B.

### Discussion
`PrimitiveNamedForDomainTypeVisitor` runs cross-file, in two phases.

1. **Collect.** Record every project **struct newtype** (a struct with exactly one stored
   instance property of a bare primitive) as `wrapperName → carrier`, and every function
   parameter and stored property typed as a bare primitive as a `(name, carrier, enclosingType)`
   position.
2. **Match and emit.** Flag a position whose name (case-insensitive) equals a wrapper over the
   **same** carrier — `idempotencyKey: String` ↔ `IdempotencyKey`, `userID: String` ↔ `UserID`.

#### Why it is a separate, lower-precision rule
The name heuristic is broader than the keying rule's structural signal and has a real
false-positive tail: a name can match a wrapper by coincidence. It is a **separate opt-in rule**
so a team can adopt the high-precision keying signal
([Primitive Bypassing Its Domain Type](primitive-bypassing-its-domain-type.md)) without this
one. Both are `Info` and opt-in.

#### The wrapper's own backing field is never flagged
A wrapper whose backing property happens to share its name — `struct Percentage { let percentage: Int }`
— is not flagged for its *own* field: a position whose enclosing type is the matching wrapper is
skipped, so the rule never nags the very cure it is enforcing.

#### Generic wrapper names are not triggers
The name signal only earns its keep when the wrapper name is *distinctive*. A project may declare
`struct Name` or `struct Value`, but `name: String` and `value: String` are everyday parameter
names that collide by coincidence — measured as ~110 hits across real projects (vapor's `Name`
alone accounted for 71), nearly all false positives. So a wrapper whose name is a common word
(`Name`, `Value`, `Text`, `Image`, `Code`, `Message`, …) is skipped; a distinctive one
(`IdempotencyKey`, `SessionID`, `ByteCount`) still fires. The guard is Variant-B-only — a
generic-named wrapper used as a *key* is still a valid finding for
[Primitive Bypassing Its Domain Type](primitive-bypassing-its-domain-type.md).

#### Recognized wrapper shapes
A wrapper is a `struct` with a single stored primitive property, a `struct` declaring
`typealias RawValue = <primitive>`, or an `enum` with a primitive raw type (`enum Currency: String`).
The generic-name stop-list applies to all of them, so an `enum Status: String` does not turn
every `status: String` into a finding.

#### Known limitations
- **Exact name match only.** `idempotencyKey: String` matches `IdempotencyKey`, but `key: String`
  inside an idempotency-flavored type does not — the broader contains/context heuristic is noisier
  and deferred to Variant C.
- Suppress with `// swiftprojectlint:disable Primitive Named For Its Domain Type`.

### Non-Violating Examples
```swift
// The position is already typed as the domain newtype.
struct IdempotencyKey { let value: String }
func handle(idempotencyKey: IdempotencyKey) {}
```

```swift
// The wrapper's own backing field is not flagged against its own type.
struct Percentage { let percentage: Int }
```

```swift
// No wrapper of that name exists — nothing to enforce.
struct IdempotencyKey { let value: String }
func cache(key: String) {}      // 'key' does not name IdempotencyKey
```

### Violating Examples
```swift
// The parameter names the domain type but is typed as the raw carrier.
struct IdempotencyKey { let value: String }

func process(idempotencyKey: String) {}   // ← flagged: name matches IdempotencyKey, type is String
```

```swift
// Same, as a stored property in another file — name matches the wrapper, type is its carrier.
struct UserID { let raw: UUID }

struct Session {
    let userID: UUID                       // ← flagged: name matches UserID, type is the raw UUID
}
```

**Suggestion:** Type the position as the domain newtype (`IdempotencyKey`, `UserID`) so the
identity is enforced by the type instead of a bare primitive any value can impersonate.

### As a Property-Test Seed

A finding is exported by `--format pbt-seeds` with `kind: carrier` and a `symbol` naming the
**domain type** — not the mistyped position, and not a function. A carrier is a type that owes laws
the raw primitive cannot state: `Percentage` can own `0...100`; `Int` cannot.

Two things a consumer needs to know about this kind:

- **The `symbol` is a type name.** Every other analysable kind names something callable. Templates
  that state laws over a carrier type (round-trip, model laws, value semantics) are the consumers
  this kind is for; anything expecting a function should skip it.
- **The `file` is the *use site*, not the type's declaration.** The rule fires where the primitive
  is used, and the domain type it names usually lives in another file. A consumer joining on
  `(file, symbol)` will miss; join on the type name.

`carrier` is analysable — the subject can be named and laws proposed for it — but it never demotes
to `restricted-function`, which promises a callable.

---
