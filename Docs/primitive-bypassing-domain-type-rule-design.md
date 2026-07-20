# Design Spike: Primitive Bypassing Its Domain Type

**Status:** Both variants shipped as separate opt-in Architecture rules, following the
[Could Hoist](could-hoist-to-protocol-extension-rule-design.md) precedent of shipping a spike's
variants as distinct rules. Variant A →
[Primitive Bypassing Its Domain Type](rules/primitive-bypassing-its-domain-type.md) (the
structural inconsistent-keying signal); Variant B →
[Primitive Named For Its Domain Type](rules/primitive-named-for-its-domain-type.md) (the
name-correspondence signal). Variant A's shipped form is tightened from §3's first sketch: it
fires only when the raw-keyed and wrapper-keyed maps share the **same value type** (the
false-positive guard for a carrier as common as `String`), and v1 recognizes **struct
newtypes** and **`Dictionary`** only — see §3.1 and §4. This is the *enforcement* complement to
a smell no linter can detect directly (primitive obsession): the disease is semantic; the cure,
once applied, is syntactic — and that asymmetry is the whole justification for the rules. See §1.

## 1. Problem statement — why detecting the smell is undecidable but policing the cure is not

"Primitive obsession" is modeling a domain concept — a dedup key, an email, a percentage, a
currency amount — as a bare `String`/`Int`/`Double` that any value of that primitive can
impersonate. It is a genuine smell, but it is **not something a linter can detect**, because
the fact that a particular `String` "is really an idempotency key with a stability rule" lives
in the developer's head, not in the syntax. A tool that tried would be guessing from parameter
names, and would drown in false positives — the same wall
[Shared Domain-Enum Field](rules/shared-domain-enum-field.md) hits, one level worse. This is
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
sources, exactly as [Shared Domain-Enum Field](rules/shared-domain-enum-field.md) requires the
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
([Primitive Named For Its Domain Type](rules/primitive-named-for-its-domain-type.md)) — a team
can adopt Variant A's structural signal without it. **v1 uses exact name match only**
(`idempotencyKey` ↔ `IdempotencyKey`, case-insensitive); the broader contains/context form
(`key: String` inside an `Idempotenc*`-named type) is the noisier tail and is deferred until it
can be measured against real projects, the same caution the broad
[Could Hoist](could-hoist-to-protocol-extension-rule-design.md) variant earned. The rule never
flags a wrapper's own backing field (a position whose enclosing type is the matching wrapper is
skipped).

### Phases (both variants)

1. **Collect wrappers.** Walk all declarations; record each qualifying `W` with its carrier `P`
   and its conventional field/parameter name(s). Cross-file, because the wrapper and its
   bypass usually live apart — the same reason
   [Shared Domain-Enum Field](rules/shared-domain-enum-field.md) needs cross-file analysis.
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

- **Complement, not overlap, with [Shared Domain-Enum Field](rules/shared-domain-enum-field.md)
  and [Duplicate Struct Shape](rules/duplicate-struct-shape.md):** those two say *"a type is
  missing — create it."* This one says *"the type exists — use it."* Together they cover both
  halves of the modeling loop: extract the abstraction, then enforce its adoption.
- **[Magic Number](rules/magic-number.md)** is the degenerate case — a raw literal with no
  wrapper at all; this rule is what becomes possible once that literal has been given a type.
