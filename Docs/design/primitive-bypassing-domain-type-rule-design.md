# Design Spike: Primitive Bypassing Its Domain Type

**Status:** Both variants shipped as separate opt-in Architecture rules, following the
[Could Hoist](could-hoist-to-protocol-extension-rule-design.md) precedent of shipping a spike's
variants as distinct rules. Variant A →
[Primitive Bypassing Its Domain Type](../rules/primitive-bypassing-its-domain-type.md) (the
structural inconsistent-keying signal); Variant B →
[Primitive Named For Its Domain Type](../rules/primitive-named-for-its-domain-type.md) (the
name-correspondence signal). Variant A's shipped form is tightened from §3's first sketch: it
fires only when the raw-keyed and wrapper-keyed maps share the **same value type** (the
false-positive guard for a carrier as common as `String`), and v1 recognizes **struct
newtypes** and **`Dictionary`** only — see §3.1 and §4. This is the *enforcement* complement to
a smell no linter can detect directly (primitive obsession): the disease is semantic; the cure,
once applied, is syntactic — and that asymmetry is the whole justification for the rules. See §1.
Variant C's wrapper-shape widening (raw-value enums, `RawRepresentable` structs) has since shipped
to both rules, and the field sweep it triggered added a symmetric value-type guard to Variant A
(§8). `Set` support was then implemented, measured, and **rejected** — it flooded (296 hits, 248 in
one project), because element-only sets lack the linking signal precision needs (§8). The broad
Variant B name form remains deferred.

## 1. Problem statement — why detecting the smell is undecidable but policing the cure is not

"Primitive obsession" is modeling a domain concept — a dedup key, an email, a percentage, a
currency amount — as a bare `String`/`Int`/`Double` that any value of that primitive can
impersonate. It is a genuine smell, but it is **not something a linter can detect**, because
the fact that a particular `String` "is really an idempotency key with a stability rule" lives
in the developer's head, not in the syntax. A tool that tried would be guessing from parameter
names, and would drown in false positives — the same wall
[Shared Domain-Enum Field](../rules/shared-domain-enum-field.md) hits, one level worse. This is
the deliberate blind spot the type system has too: the constraint was never written down where
any analyzer — compiler or linter — could see it.

But the moment someone *cures* the smell — declares `struct IdempotencyKey` around the
`String`, or a `Percentage` around the `Int` — the domain knowledge is suddenly **in the type
system**, where an analyzer *can* see it. And now a new, tractable question appears: is every
site that handles this concept actually using the domain type, or are some still trafficking in
the raw primitive it was meant to replace?

That second question is decidable and low-false-positive, because the wrapper type is the
ground truth the first question lacked. A linter cannot tell you to *create* `IdempotencyKey`;
once it exists, it can tell you where you *bypassed* it.

| Rule | Starts from | Asks |
|---|---|---|
| Shared Domain-Enum Field | 3+ types sharing a project-enum field | is there a *missing protocol*? |
| Duplicate Struct Shape | concrete types with a wide shared shape | is there a *missing type*? |
| Magic Number | a raw numeric literal | should this be a *named constant*? |
| **This spike** | a project newtype `W` over primitive `P` | is a raw `P` being used where `W` exists? |

The through-line: the other three infer a *missing* abstraction (and pay for it in false
positives); this one enforces a *present* one (and is cheap because the abstraction is already
declared).

## 2. What counts as a "domain wrapper type"

The rule only arms itself against project-declared newtypes over a single primitive. A type
`W` qualifies when, in the analyzed sources, it is one of:

- a `struct`/`enum` with exactly one stored property whose type is a primitive
  (`String`, the integer/float families, `Bool`, `UUID`, `URL`, `Data`, `Decimal`), **or**
- a `RawRepresentable` conformer whose `RawValue` is one of those primitives.

Call that primitive `P` the wrapper's *carrier*. `IdempotencyKey` (carrier `String`),
`Percentage` (carrier `Int`), `Money`/`Cents` (carrier `Int`/`Decimal`), `UserID` (carrier
`UUID`) all qualify. Framework types never qualify — the wrapper must be declared in the
sources, exactly as [Shared Domain-Enum Field](../rules/shared-domain-enum-field.md) requires the
enum to be project-declared. That requirement is again the false-positive guard: a `String`
somewhere is meaningless; a `String` *where `IdempotencyKey` exists and is named for* is a
signal.

## 3. Detection design — two variants, by precision

Following the [Could Hoist](could-hoist-to-protocol-extension-rule-design.md) discipline of
leading with the tractable variant and being honest about what it misses.

### Variant A — inconsistent keying (highest precision, shipped)

Fire when a `Dictionary` is keyed by the raw carrier `P` **and a wrapper `W` over `P` keys a
map to the *same value type* `V` elsewhere in the sources.** `[String: Response]` next to a
`[IdempotencyKey: Response]` is a real inconsistency, not a naming guess — one map enforces the
domain identity and the other launders it back to a bare string, which is precisely the
dedup-key confusion that produces a double charge.

The **matching value type is the false-positive guard**, and it is load-bearing: `String` keys
thousands of unrelated dictionaries, so firing on every `[String: X]` merely because some
`String` newtype exists would flood. Requiring the raw-keyed and wrapper-keyed maps to share
`V` is what makes the signal structural (two keyings of one mapping that disagree) rather than
lexical. v1 recognizes struct newtypes and `Dictionary` only; `Set` (no `V` to match on) and
enum/`RawRepresentable` wrappers are deferred to Variant C.

### Variant B — raw carrier in a named domain position (shipped as a separate opt-in rule)

Fire when a function parameter or stored property is typed `P` but *named* for the wrapper's
concept — `idempotencyKey: String` where `IdempotencyKey` exists. This is the name-correspondence
heuristic, and it *will* have false positives (a generic `key: String` in a cache utility has
nothing to do with `IdempotencyKey`), so it ships as its own opt-in rule
([Primitive Named For Its Domain Type](../rules/primitive-named-for-its-domain-type.md)) — a team
can adopt Variant A's structural signal without it. **v1 uses exact name match only**
(`idempotencyKey` ↔ `IdempotencyKey`, case-insensitive); the broader contains/context form
(`key: String` inside an `Idempotenc*`-named type) is the noisier tail and is deferred until it
can be measured against real projects, the same caution the broad
[Could Hoist](could-hoist-to-protocol-extension-rule-design.md) variant earned. The rule never
flags a wrapper's own backing field (a position whose enclosing type is the matching wrapper is
skipped).

### Variant C — wider wrapper and container shapes

Variants A and B first recognized only the cleanest wrapper shape — a `struct` with a single
stored primitive property. Variant C widens that. One item shipped (measured), one was tried and
rejected (measured), one stays deferred.

- **Enum and `RawRepresentable` wrappers — shipped, both rules.** `enum Currency: String` and a
  `struct` declaring `typealias RawValue = <primitive>` (covering `RawRepresentable` structs with
  a *computed* `rawValue` the single-stored-property shape misses) are now recognized. The worry
  was that an enum raw type is *also* a serialization detail — and the measurement (§8) proved it
  founded, but not in the way expected: enums didn't make the wrappers bad, they exposed a latent
  hole in Variant A's *value*-type guard. Raw-value enums are commonly keyed to bare primitives
  (`[Currency: String]`), and `[String: String]` maps are everywhere, so the value-type match
  fired on coincidence — 71 of 72 sweep hits had a bare-primitive value. The fix was a second
  guard symmetric to the first: as the *key* wrapper must be distinctive, the matched *value*
  type must be too (ubiquitous scalars and `String` excluded; `UUID`/`Data`/`Decimal` kept).
  With it, Variant A returned to one real finding; Variant B's expansion was all distinctive
  domain-enum names (`Tier`, `Severity`, `Phase`, …) and needed no new guard beyond the stop-list.

- **`Set` support — tried, measured, rejected.** `Set<UserID>` beside `Set<String>` is the
  Variant A inconsistency *without a value type to match on* — and the value type is precisely A's
  false-positive guard. The plan was to borrow a "different guard": fire a raw `Set<P>` only when a
  `Set<W>` over the same carrier exists **and** `W` is independently corroborated as an identity
  type (used as a distinctive-value dictionary key `[W: V]` elsewhere). It was implemented and
  swept — and it flooded: **296 findings across 32 projects, 248 from a single project** where one
  corroborated wrapper (`InteractionInvariantFamily`) flagged every unrelated `Set<String>` across
  115 files. The guard gates the *wrapper*'s legitimacy but nothing links a *specific* `Set<String>`
  to it — a Set has no second type to provide that link, so one legitimate wrapper taints every raw
  set of the same carrier. Reverted. Element-only sets simply lack the signal precision needs; see
  §8. (A proximity guard — only a `Set<P>` co-located with a `Set<W>` in one type — might narrow it,
  but co-location is weak evidence and was not pursued.)

- **The broad Variant B name form — deferred.** `key: String` inside an `Idempotenc*`-named type,
  rather than an exact `idempotencyKey ↔ IdempotencyKey` match — the same "measure the noisy tail
  first" bucket, still unmeasured.

The through-line holds, and now cuts both ways: a shape ships only once its precision is argued
*and* measured. The enum item cleared that bar (and taught a guard); Set was measured against it
and **failed**; the broad name form is still unmeasured.

### Phases (both variants)

1. **Collect wrappers.** Walk all declarations; record each qualifying `W` with its carrier `P`
   and its conventional field/parameter name(s). Cross-file, because the wrapper and its
   bypass usually live apart — the same reason
   [Shared Domain-Enum Field](../rules/shared-domain-enum-field.md) needs cross-file analysis.
2. **Scan for bypasses.** For Variant A, index every `Dictionary`/`Set` key type and report `P`
   keyings that co-exist with a `W` keying. For Variant B, report `P`-typed parameters/
   properties whose name matches a collected wrapper's concept.
3. **Suppress the deliberate.** A site already using `W`, or one carrying
   `// swiftprojectlint:disable Primitive Bypassing Its Domain Type`, is dropped.

## 4. The inconvenient truth

Variant A catches the *safe* cases and misses the *common* one. The typical bypass is not two
disagreeing dictionaries in the same module — it is a lone helper that still takes `key: String`
because whoever wrote it never reached for the domain type. That is Variant B territory, and
Variant B is a naming heuristic with a real false-positive tail. So this rule, like the smell it
chases, has an irreducible semantic residue: even *with* the domain type in hand, deciding
whether a given raw `String` "should have been" the wrapper sometimes still needs a human. The
rule shrinks that residue; it does not eliminate it. It is `Info` and opt-in for that reason.

What the rule buys, honestly stated: it converts "we have an `IdempotencyKey` type — please use
it everywhere" from a code-review reminder that decays into a mechanical, cross-file check that
does not. Detecting the disease is undecidable; policing the cure is merely hard.

## 5. Severity and category

- **Category:** Architecture (alongside Shared Domain-Enum Field and the protocol-extraction rules).
- **Severity:** Info, **opt-in** — matches the domain-modeling rules' posture; a project may
  keep a raw primitive on purpose, and the rule must not block a build over a judgment call.

## 6. Motivating example

`SwiftIdempotency` declares `IdempotencyKey` as a newtype over `String`, whose initializers are
named to force the stability question (`fromEntity:`, `fromAuditedString:`) and whose dangerous
constructors are deliberately absent. That is the cure for primitive obsession applied exactly
where the stakes are highest — a mis-keyed dedup token is a double charge, not a cosmetic
nit. The gap the compiler leaves open: nothing stops a *neighboring* function from still taking
`key: String`, or a cache from being `[String: Response]`, quietly reintroducing the very
stringly-typed key the wrapper was built to abolish. Variant A flags the inconsistent cache
keying with high confidence; Variant B flags the `key: String` helper with a name heuristic and
an `Info` severity that admits it is advice, not a verdict.

## 7. Relationship to existing rules

- **Complement, not overlap, with [Shared Domain-Enum Field](../rules/shared-domain-enum-field.md)
  and [Duplicate Struct Shape](../rules/duplicate-struct-shape.md):** those two say *"a type is
  missing — create it."* This one says *"the type exists — use it."* Together they cover both
  halves of the modeling loop: extract the abstraction, then enforce its adoption.
- **[Magic Number](../rules/magic-number.md)** is the degenerate case — a raw literal with no
  wrapper at all; this rule is what becomes possible once that literal has been given a type.

## 8. Field measurement — a 32-project sweep

§3 and §4 promised Variant B would be "measured before trust." It has been: both rules were run
(opt-in, via `enabled_only`) across 32 real Swift projects — the author's own apps and packages
plus vapor, hummingbird, pointfreeco, ViewInspector, and swift-server ecosystem repos.

**Variant A held.** Exactly one finding in 32 projects, and it was real: Hummingbird's
`FileMiddleware` keys a `[String: MediaType]` map beside a `[FileExtension: MediaType]` map — the
raw `String` bypasses the `FileExtension` type. Zero false positives anywhere else. The
structural signal is as precise as designed, which retro-justifies shipping it first and un-gated.

**Variant B flooded, then was fixed by measurement.** The first run returned **114 hits, ~95% of
them one coincidence**: a generic-word newtype colliding with an everyday parameter name — vapor's
`Name` (71) and `Value` (13); `Text`, `Image`, `Code`, `Message`, `Modifier` elsewhere. Precision
was gated entirely by *how distinctive the wrapper name is*. Adding a generic-name stop-list (skip
`Name`/`Value`/`Text`/… as triggers) collapsed **114 → 9**, and every survivor is a distinctive
domain type that is plausibly a true positive: `ByteCount` (4) and `SessionID` (2) in vapor,
`Command`/`File` in pointfreeco, and `FileExtension` in hummingbird — the very type its Variant A
finding names.

| across 32 projects | Variant A | Variant B (before) | Variant B (after stop-list) |
|---|---|---|---|
| hits | 1 | 114 | 9 |
| character | 1 real, 0 false | ~95% generic-word coincidence | survivors all distinctive |

The lesson, on record: the name heuristic is trustworthy only for *distinctive* wrapper names, and
a generic-name stop-list is the cheap guard that makes it so. Variant C's broader contains/context
form must clear the same bar — measured, not assumed — before it ships.

**A second sweep, after adding enum/`RawRepresentable` wrappers (Variant C).** Recognizing
raw-value enums re-ran across the same 32 projects and immediately blew Variant A up from 1 hit to
**72** (SwiftInferProperties 46, VernissageServer 16, SwiftAssist 9). The cause was not the enums
but what they revealed: **71 of the 72 keyed a bare-primitive value** (`[…: String]`×58,
`[…: Int]`×13), and only the lone distinctive-value hit (`[…: MediaType]`, Hummingbird) was real.
The value-type guard — A's whole basis — is worthless when the value is itself ubiquitous. Adding
a trivial-value-type exclusion (symmetric to the wrapper-name stop-list: the matched value must be
distinctive, not `String`/`Int`) dropped Variant A back to **1**, the real finding intact. Variant
B's enum expansion (~9 → ~59) needed no such fix — it was all distinctive domain-enum names
(`Tier`×19, `Repo`×8, `Severity`×7, `Phase`, `ByteCount`, `SessionID`, `Role`, …) matched against
same-named `String` positions, the name signal working as designed.

| after enum widening | Variant A | Variant A + value guard | Variant B |
|---|---|---|---|
| hits across 32 projects | 72 | 1 | ~59 |
| character | 71 bare-primitive-value false | 1 real (`MediaType`) | distinctive domain-enum names |

The meta-lesson, twice now: **each rule's guard is only as strong as the distinctiveness of the
thing it keys on** — the wrapper name for B, the value type for A. Widen the wrappers and any
weakness in that guard surfaces at once. Both guards are now symmetric: key *and* value must be
distinctive.

**A third sweep killed a feature: `Set` support.** The plan (Variant C) was to fire a raw `Set<P>`
only when a `Set<W>` existed *and* `W` was corroborated as an identity type via a distinctive-value
dictionary key — borrowing A's validated signal for a container that has no value type of its own.
Implemented and swept, it returned **296 hits, 248 from SwiftInferProperties alone**, where a single
corroborated wrapper (`InteractionInvariantFamily`) flagged every unrelated `Set<String>` across 115
files. The diagnosis is clean and final: corroboration proves the *wrapper* is real, but with no
value type there is nothing to link a *specific* `Set<String>` to that wrapper — so one legitimate
wrapper taints every raw set of its carrier. The feature was reverted.

| the three sweeps | outcome |
|---|---|
| Variant B name heuristic | 114 → 9 via a generic-name stop-list — **kept** |
| Variant A + enum wrappers | 72 → 1 via a trivial-value guard — **kept** |
| Variant C `Set` support | 296, un-guardable with the available signal — **rejected** |

The discipline is the point, and it now has a negative to prove it: "measure before trust" only
means something if measurement is allowed to say *no*. Two guards were found by measurement; one
whole shape was discarded by it. A shape that cannot be made precise is not shipped dimmer — it is
not shipped.

## 9. Case study — the one true positive (Hummingbird)

The single Variant A finding that survived every guard is worth reading in full, because it is
exactly the shape the rule exists to catch — and its adjudication is exactly the posture the rule
is meant to have.

`Sources/Hummingbird/Middleware/FileMiddleware.swift:124`:

```swift
public func withAdditionalMediaType(_ mediaType: MediaType, mappedToFileExtension fileExtension: String) -> FileMiddleware {
    withAdditionalMediaType(mediaType, mappedToFileExtension: MediaType.FileExtension(fileExtension))
}
public func withAdditionalMediaType(_ mediaType: MediaType, mappedToFileExtension fileExtension: MediaType.FileExtension) -> FileMiddleware {
    withAdditionalMediaTypes(forFileExtensions: [fileExtension: mediaType])
}

public func withAdditionalMediaTypes(forFileExtensions extensionToMediaTypeMap: [String: MediaType]) -> FileMiddleware {  // ← flagged
    withAdditionalMediaTypes(
        forFileExtensions: extensionToMediaTypeMap.reduce(into: [MediaType.FileExtension: MediaType]()) {
            $0[.init($1.key)] = $1.value
        }
    )
}
```

`MediaType.FileExtension` is a newtype over `String`, and the canonical internal map is
`[MediaType.FileExtension: MediaType]`. The flagged method is a public overload that accepts the
*raw* `[String: MediaType]` and, on the very next line, `.reduce`s each `String` key through
`MediaType.FileExtension.init` to reach the domain-keyed form. The rule saw a `[String: MediaType]`
map beside a `[MediaType.FileExtension: MediaType]` map — same value type, one keyed by the
wrapper, one by the raw carrier — and that is precisely what it reported. Zero false positives: the
inconsistency is real, and the `.init($1.key)` conversion two lines down is the proof.

**The adjudication is the point.** This is not a bug — it is a deliberate ergonomic overload: the
`[String: MediaType]` entry point exists so callers can pass string literals without wrapping each
one, and the method pays for that convenience with a single explicit conversion at the boundary.
A reviewer looks at it and, reasonably, keeps it. That is the whole design in one example:

- the rule's job is to **surface the seam** — a place where a domain type exists but a raw
  primitive still crosses a boundary — with enough precision that the seam is real;
- the human's job is to **rule on intent** — bug, or intentional convenience?

An `error`-severity rule that forced this to change would be wrong; an `Info`, opt-in rule that
draws the reviewer's eye to it is exactly right. The one true positive in 32 projects turning out
to be an intentional overload is not a disappointment — it is the honest ceiling of static
enforcement restated: **a tool finds the divergence; a human still adjudicates the intent.**
