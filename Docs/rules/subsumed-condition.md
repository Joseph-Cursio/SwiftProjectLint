[← Back to Rules](RULES.md)

## Subsumed Condition

**Identifier:** `Subsumed Condition`
**Category:** Code Quality
**Severity:** Info

### Rationale

An operand of an `||` or `&&` chain that another operand implies, or is implied by, can never
change the chain's result:

```swift
static func isIntScalar(tagDescription: String) -> Bool {
    tagDescription.contains("int") || tagDescription.contains("tag:yaml.org,2002:int")
}
```

The second test implies the first, so whenever it is true the chain already is. It reads like a
second chance to match, and it is dead weight. It also usually points at the *other* operand.
The precise test states what was meant, and the loose one matches more than that:
`contains("int")` also accepts `"!hint"` and `"!point"`.

### Why it exists: mutants no test can kill

Mutation testing found this shape. On SwiftLintRuleStudio, every `||` → `&&` mutant of the three
YAML scalar classifiers (`isBoolScalar`, `isIntScalar`, `isFloatScalar`) survived, as did both
mutants in

```swift
if trimmed.isEmpty || trimmed.hasPrefix("+") || !trimmed.hasPrefix("|") { return false }
```

An empty line and a `+` line already fail to start with `|`, so the condition is
`!trimmed.hasPrefix("|")`. These mutants are *equivalent*: they change an operand that never
decides anything, so no test can tell them apart from the original. A mutation report that lists
them sends someone to write a test that cannot exist. This rule names the redundancy at the
source, which the report cannot do.

### What is read

Each operand of a flat chain, with one connective throughout, is read as a test of a string
against a literal. An `if` or `guard` condition list is read as an `&&`. The tests are:

| Operand | Read as |
|---|---|
| `x == "a"`, `x != "a"` | equality, or its negation |
| `x.contains("a")` | substring containment, **only if `x` is known to be a string** |
| `x.hasPrefix("a")`, `x.hasSuffix("a")` | prefix and suffix |
| `x.isEmpty`, `x == ""` | emptiness |
| `!p`, `(p)` | negation, and parentheses read through |

Implication is decided from the literals alone:
- an equality implies whatever its literal satisfies;
- `contains("ab")` implies `contains("a")`;
- `hasPrefix("ab")` implies `hasPrefix("a")` and `contains("b")`;
- two prefixes, neither of which extends the other, exclude each other;
- a negated operand is decided by the contrapositive.

In an `||`, an operand that implies another is redundant. In an `&&`, an operand that another
implies is redundant. Of two identical operands, the second is reported.

Anything else is **opaque**: it implies nothing and nothing implies it. The rule never reports a
redundancy it has not proved. That covers interpolated or escaped literals, different receivers
(`s.lowercased()` is not `s`), a chain mixing `&&` with `||`, and any call other than the ones
above.

### `contains` needs a string

For an array or a set, `contains` is membership, and
`modifiers.contains("fileprivate") || modifiers.contains("private")` tests two independent
elements. So `contains` is read as containment only when the receiver is known to be a string,
from any of:
- the chain itself: a `hasPrefix`, a `hasSuffix` or an `==` against a literal on the same
  receiver, since those exist only on strings;
- a receiver ending in a string-producing call or property, such as `.lowercased()`,
  `.trimmingCharacters(in:)` or `.description`;
- a name declared in the enclosing declaration as a `String` or `Substring` parameter, a local
  annotated so, a local initialised from a string literal or a string-producing call, or an
  `as? String` binding.

Without evidence, a `contains` still implies the receiver is not empty, which holds for a
collection too.

### Measured

Over 55 local repositories, the first pass reported **47** findings, and **9** were wrong. All 9
were `contains` on a collection: seven over modifier, name or conformance sets in
SwiftInferProperties, and two `components.contains("..") || components.contains(".")` in muter and
its fork. Requiring a string receiver removed all nine. It also dropped five true findings whose
types are not visible to the rule: an enum case's bound `msg`, a `merge.stderr` property, and
three test assertions on `script.text` or `$0.message`.

The remaining **33** were each read, and all 33 are operands that cannot change their chain. The
measured cases above are among them. Examples:

| Finding | What it says |
|---|---|
| `name == "Tests" \|\| name.hasSuffix("Tests")` | the equality is redundant, three times across two repositories |
| `$0 == "MainActor" \|\| $0.hasSuffix("Actor")` | the equality is redundant, twice |
| `last.hasPrefix("s:") \|\| last.hasPrefix("s")` | the precise test is redundant; worth checking whether `hasPrefix("s")` was meant |
| `trimmed.contains("<thead") \|\| … \|\| trimmed.contains("<th")` | `<th` already matches `<thead`, so the `<thead` test is redundant |
| `!currentViewName.isEmpty && currentViewName.hasSuffix("View")` | the suffix already implies non-empty |

Many are harmless documentation of intent, which is why the rule is `Info`. The ones worth reading
are those where the loose operand matches more than the code means, like `contains("int")` and
`hasPrefix("s")`.

### Non-Violating Examples

```swift
x == "Package.swift" || x == ".swiftpm"                       // independent
x.hasSuffix(".xcodeproj") || x.hasSuffix(".xcworkspace")       // independent
modifiers.contains("fileprivate") || modifiers.contains("private")  // membership, not containment
s.lowercased().hasPrefix("ab") || s.hasPrefix("a")            // different receivers
```

### Violating Examples

```swift
tagDescription.contains("int") || tagDescription.contains("tag:yaml.org,2002:int")
trimmed.isEmpty || trimmed.hasPrefix("+") || !trimmed.hasPrefix("|")   // two redundant operands
name == "Tests" || name.hasSuffix("Tests")
```

**Suggestion:** Delete the operand that cannot decide anything. If it is the precise one and
states the intent, narrow the other instead, because a loose test that subsumes a precise one
usually matches more than was meant.
