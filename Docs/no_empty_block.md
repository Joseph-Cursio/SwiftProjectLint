# `no_empty_block` — Configuration Rationale

```yaml
no_empty_block:
  disabled_block_types: [closure_blocks]
```

## What the rule does

SwiftLint's [`no_empty_block`](https://realm.github.io/SwiftLint/no_empty_block.html) flags any block (`{ }`) that contains neither statements nor comments. The intent is to catch *accidentally* empty bodies — a stub the author forgot to fill in, or a paste error that nuked the original contents.

The rule recognises four block kinds, configurable via `disabled_block_types`:

| Block kind | Example |
|---|---|
| `function_bodies` | `func foo() {}` |
| `initializer_bodies` | `init() {}` |
| `statement_blocks` | `if cond {}`, `for x in xs {}`, `do {}` |
| `closure_blocks` | `Button("Tap", action: {})` |

By default all four are checked.

## What we changed and why

We opted into the rule but disabled the `closure_blocks` category. The rule still fires on empty function bodies, initializers, and statement blocks — where an empty body is almost always a mistake.

The trigger was the first run of the rule against this codebase:

- **72 violations across 18 files.**
- **~50 of those (~70%)** were intentional empty closures passed as no-op callbacks to view fixtures in tests:
  ```swift
  let view = ContentViewActions(
      selectedDirectory: "",
      onSelectRules: {},
      onSelectDirectory: {},
      onAnalyzeProject: {}
  )
  ```
- The remaining ~22 hits were genuine empty bodies that *did* warrant an explicit `// no-op` comment — empty `public init()`s, an `open` default implementation meant for subclasses to override, and a couple of mock-protocol stubs.

Disabling `closure_blocks` keeps the rule's value for the 22 cases that deserve a written intent marker, while not forcing 50 trivial `{ /* no-op */ }` rewrites on test fixtures where the empty closure *is* the point of the call site.

## Why not other approaches

We considered three alternatives before settling on the partial-disable:

**Annotate every empty closure with `// no-op`.** Adds 50+ lines of comment noise across the test suite. The closures are passed positionally as no-op handlers — the variable name (`onSelectRules`, `onDismiss`) already communicates intent. A `// no-op` comment inside the closure adds nothing that the surrounding context doesn't already carry.

**Drop the rule entirely.** Throws out real signal. The 22 non-closure cases were legitimately worth annotating — an empty `override func finalizeAnalysis() { }` reads ambiguously (forgotten implementation? intentional skip?) whereas `override func finalizeAnalysis() { // no-op: this visitor has no aggregation step }` is unambiguous.

**Add per-line `// swiftlint:disable:next no_empty_block` suppressions.** Worse than the comment approach — 50 disables, each indistinguishable from a real suppression of a real problem, and the project's `swiftlint_suppression` lint rule already discourages this pattern.

## When to re-evaluate

Reconsider re-enabling `closure_blocks` if either becomes true:

- An empty-closure bug actually slips into production code (not test fixtures). Then the rule's value at closure sites would have been demonstrated.
- We adopt a `() -> Void` typealias like `Action` and update test fixtures to use `Action.noop` (or similar) consistently. Once test sites no longer use `{}` literally, the rule's noise floor drops to near zero and full enabling becomes cheap.

Until then, the current config is the right tradeoff.
