# When the tool already knows and cannot say it

**Status:** observation, written up after a working session. No code change proposed here; the
concrete follow-on is [`Docs/design/seam-inventory-design.md`](design/seam-inventory-design.md).

Two things happened in one session that look unrelated and are the same thing.

## 1. A rule that could find a bug, but not in the spelling it was written in

`SwiftLintRuleStudio` had a title menu of eleven `Button`s against a twelve-case enum. It silently
omitted one destination — Config Map was reachable from the sidebar and from nowhere else. That is
exactly what `parallel-list-drift` exists to catch, and written as an array literal it catches it,
naming the missing case:

> `offeredSections` (array, 11 entries) agrees with `AppSection` (enum) on 11 entries but is
> missing 1: **configMap**.

Written as eleven sibling calls it reported nothing, for two narrow reasons: `Button` is not a
`RegistrationVerb`, so the run was never collected; and the first name-like argument is the *label*
(`"Enabled Rule Violations"`), which normalizes nowhere near the case name it belongs to.

The knowledge was there. The **carrier** was missing. Closing it took about thirty lines and moved
the corpus count by zero — 17 findings before, 17 after — because no other code in 18 repositories
has the defect. It is worth having anyway: the next menu written this way is reported instead of
shipped.

## 2. A rule that is silent for the right reason, and unhelpful anyway

Writing a test for `SwiftFormatRuleStudio.ImpactModel` needed one fact: **is there a seam?** There
was — `cli` and `reader` are `init` parameters with defaults — and finding it took a `grep` for
`let cli` and `init(`.

`missing-dependency-injection` had nothing to say, correctly. It reports the *absence* of a seam,
and this type has one. It discriminates well, too: `ViolationInspectorView` builds its view model
inline but carries a `#if DEBUG init(viewModel:)` and is **not** reported, while
`SwiftUMLStudio.ContentView` has the same shape without the initialiser and **is**. Same syntax,
opposite verdicts, decided by whether the seam exists.

So the rule is right and the question still went unanswered, because it is the *other* question.

## The shape

Every rule in this suite reports an absence: a missing seam, an unreachable closure, a drifted
list, a stamp nobody can pin. That is what a linter is for, and a rule that fires on correct code
is noise.

But the suite is not only used to find faults. It is used while **working** — and the questions
that come up then are positive ones:

| While fixing | The question is | Answered by |
|---|---|---|
| anything | *what is wrong here?* | every rule |
| writing a test | *where can I reach this from?* | nothing |
| naming a law | *what is already pure?* | `pbt-seeds`, partially |
| refactoring a view | *what does this actually depend on?* | nothing directly |

`--format pbt-seeds` is the one place the suite already answers a positive question — *here are the
pure functions, hand them to `swift-infer`*. It is the model for what is missing elsewhere, and the
proof that a positive output need not be noise: it is a **separate output**, not a finding, so it
costs nothing to a reader who wants faults.

## What follows from it

1. **A carrier gap is worth closing even at zero findings.** The measurement that matters is *does
   it report the defect when the defect exists*, not *did the count move*. Judging carrier work by
   corpus delta would have rejected the `parallel-list-drift` fix, which found nothing and would
   have caught the bug.

2. **A positive inventory belongs in an output, never in a rule.** See the design note. The rule
   set stays a fault detector; the inventory is a different question asked of the same AST.

3. **Silence has two meanings and the tool cannot distinguish them.** "No finding" means either
   *this is fine* or *this shape is invisible to me*. Case 1 above was the second, and looked
   exactly like the first for months. That is an argument for occasionally checking a rule against
   a defect you already know about — the corpus sweep will not surface what the rule cannot see.
