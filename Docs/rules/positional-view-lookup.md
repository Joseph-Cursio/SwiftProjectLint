[← Back to Rules](RULES.md)

## Positional View Lookup

**Identifier:** `Positional View Lookup`
**Category:** Testability
**Severity:** Warning

### Rationale

This rule comes from Jon Reid's article
[Find SwiftUI Views in Unit Tests, the Robust Way](https://qualitycoding.org/find-swiftui-views-unit-tests/)
on [Quality Coding](https://qualitycoding.org), part of his series on test-driving SwiftUI. Its
canonical example, its comparison of the three ways to find a view, and its recommendation of
accessibility identifiers wrapped in intention-revealing finder helpers are his. The rule
automates the first half of that advice: spotting the lookups that walk.

A ViewInspector test can reach a view two ways: walk to it, or search for it.

```swift
try sut.inspect().vStack().hStack(1).button(0)                    // walks
try sut.inspect().find(viewWithAccessibilityIdentifier: "increment") // searches
```

The walk restates the layout. Swap the two buttons and `button(0)` quietly reaches the other one,
so the test now checks the wrong view, which is worse than a failing test. Extract the buttons
into their own view, wrap them in a container, or let the compiler insert a wrapper, and the chain
breaks even though nothing a user sees has changed. The search depends only on the identifier.

The compiler case has happened. Swift 6.0 (Xcode 16.0–16.2) wrapped every custom view's body in an
implicit `AnyView`, and every chain that crossed a custom view's body boundary gained a node it did
not expect. ViewInspector's own fix added `.implicitAnyView()` to 225 lines of its test suite, and
none of those lines was a `find`. Searches survived; walks needed repair. The library made the same
kind of change again for iOS 27, where `ViewBuilder` produces `TupleContent` and chains spelling
`.tupleView(n)` must become `.tupleContentView(n)`.

A test should fail when behaviour breaks, and only then. A walk also fails when the layout changes,
and when it does not fail it may be checking the wrong view. Tests that break on every refactor
get refactoring stopped, which is the opposite of what they are for.

### What is reported

A chain is read from an inspected root: `.inspect()`, the parameter of an inspection-relay
closure (`sut.inspection.inspect { view in … }`, `sut.on(\.didAppear) { view in … }`), `self`
inside `extension InspectableView`, a parameter or property typed `InspectableView`, or a local
bound to any of these. Most walks in real tests are split across statements, so locals are
followed back:

```swift
let stack = try sut.inspect().vStack()   // one step: not reported
let button = try stack.button(0)         // reported: an index into the stack
```

Four shapes are reported, at the first one in each chain:

| Shape | Example | Why |
|---|---|---|
| An index | `hStack(1)`, `view(Row.self, 2)`, `hStack[1]`, `vStack().first`, `toolbar().item(2)`, `find(Row.self).text(0)` | Picks a sibling by its order. Reorder the siblings and the lookup fails, or reaches a different view of the same type. |
| An ordinal over search matches | `findAll(ViewType.Toggle.self)[1]`, `findAll(…).last`, `find(ViewType.Button.self, skipFound: 2)` | Picks the nth match in tree order. Reorder the views and the test silently checks a different one. |
| A second structural step since the last search | `inspect().navigationStack().vStack()` | Restates two levels of nesting. Any wrapper in between breaks it. |
| `parent()` | `find(text: "Name").parent().parent()` | Climbs a fixed number of levels, so it encodes how deeply the view is nested. |

A chain is reported once, at its first positional step. A view picked by position becomes a new
anchor of its own type: `let row = try stack.hStack(1)` is reported, and `row.text()` afterwards
is not reported again, though another index such as `row.text(0)` is.

An index counts the receiver's children, so what it picks depends on the receiver. A custom view
or modifier has as its children every view its body builds at the top level, as a sheet's content
does. ViewInspector hands back such a receiver, typed `View<Row>` or `ViewModifier<Card>`, for:

- a view reached by `find(Row.self)` or `view(Row.self)`, a `ForEach` row reached by
  `view(Row.self, 2)`, and each match of `findAll(Row.self)`;
- a modifier reached by `modifier(Card.self)`, or inspected itself (`CardModifier().inspect()`,
  which the rule recognises by name: see Known Limitations);
- the `view` an inspection relay hands its closure;
- a parameter typed `InspectableView<ViewType.View<Row>>` or
  `InspectableView<ViewType.ViewModifier<Card>>`, and `self` in
  `extension InspectableView where View == ViewType.View<Row>`.

With a body of `Text("Title")` and `Text("Subtitle")`, `find(HeaderView.self).text(0)` picks the
title as `text(1)` picks the subtitle, and both are reported, as are `[0]` and `.first`. `text()`
reaches the body's only view and is one level. A row index is data and is not reported, but an
index into the row is layout: in `find(ViewType.ForEach.self).view(Row.self, 2).text(0)` only
`text(0)` is reported. A bare `inspect()` is resolved differently: ViewInspector reaches the
body's first view for `inspect().text()` and `inspect().text(0)` alike, so neither is reported as
a pick.

### What is not reported

- **One step after an anchor.** `find(viewWithAccessibilityIdentifier: "count").text()` only
  asserts the found view's type. ViewInspector spells a cast and a descent the same way: `x()`
  takes the receiver's single child and asserts it is an `x`, and on a found view that child is
  the view itself. The same goes for `x(0)` and `view(MyView.self)` on a found view.
  `inspect().text()` reaches the body's first view and asserts it is a `Text`. It is one level of
  structure, and on a body of one view it fails loudly when that view changes type. Reporting it
  would mean reporting every test of a view whose body is a single `Text`. On a body of several
  views it takes the first, as `inspect().text(0)` does; see Known Limitations. A style (`ButtonStyle().inspect(isPressed:)`) or a SwiftUI view
  built in the test (`AnyView(Text("x")).inspect()`) is inspected as itself, so its first
  accessor is a cast.
- **Searches.** `find(…)` and `findAll(…)` in all their forms, including `findAll(…).first`,
  `findAll(…)[0]` and `findAll(…).first { … }`. An unpredicated `find(ViewType.Button.self)`
  depends on order too when several buttons exist, since it returns the first in the tree. But it
  is a search, and this rule is about walks; `findAll(…)[0]` is the same lookup spelled
  differently.
- **Data indices.** An index after `forEach()`, `find(ViewType.ForEach.self)`, or a parameter
  typed `InspectableView<ViewType.ForEach>` selects a row, and row order is behaviour. So does an
  index into an `actionSheet()`'s buttons. An index into a row reached with `view(Row.self, n)`
  is layout again, and is reported, as above. A row reached by a subscript, `.first` or iteration
  over the `ForEach` is a found view, so `x(0)` on it is read as a cast and only `x(1)` and above
  is reported; for a custom `Row`, ViewInspector resolves that `x(0)` through the row's body's
  first view, as it does for a bare `inspect()` (see Known Limitations).
- **A loop over every position.** `rows[index]` inside `for index in rows.indices`,
  `for index in 0..<rows.count`, `for (index, name) in expected.enumerated()`,
  `zip(rows.indices, expected)` or `rows.indices.forEach { index in … }` compares the whole
  sequence in order, as `rows.map { … } == expected` would. The index has to be the loop's own
  variable, with no `where` clause and no `if index == 1`, `guard index == 1` or `switch index`
  around the use, and a range must run to a `count`: `for index in 0..<3` picks three views, and is
  reported.
- **Named slots.** `labelView()`, `header()`, `title()`, `sheet()`, `overlay(1)`,
  `modifier(Card.self)` and the like reach a view by its role. The index on a modifier counts
  modifiers, not layout.
- **A subject the test file declares.** `GeometryProbe().inspect().geometryReader().shape()` walks
  a fixture defined a few lines above. The test owns that layout, and changing it means editing
  the same file. ViewInspector compatibility probes take this shape. Ownership follows the
  inspected view's type: only a `View` — a `Shape` or a `UIViewRepresentable`-style wrapper
  included — or a modifier or style declared in the file counts, and a walk that reaches an app
  view inside a test-declared host (`Host().inspect().find(AppView.self)`) is reported. A host
  whose body builds an app view — a state host wrapping the screen under test — owns its own
  layout but not the app view's, so a search that does not name its type
  (`host.inspect().find(ViewType.Form.self)`), a `findAll`, or a `parent()` climb inside it is
  read as walking the app's layout.
- **Anything else.** A step the rule does not recognise ends the chain, so a project's own
  helpers (`sut.inspect().pegColor(1)`) are not read as accessors. A finder helper the file
  declares in `extension InspectableView` under an accessor's name — `button(.increment)` — is
  read as the helper when the call fits its parameters, unless its argument is an `Int` for
  certain — an integer literal, a name bound to one or declared `Int`, an element of a range or
  `indices`, or arithmetic on one such as `second + 1` — where the helper takes none: a helper
  `find(_ id: String)` does not hide `find(ViewType.HStack.self)`. A comparison, a ternary or a
  concatenation is not arithmetic, so `button(pages > 1 ? "Next" : "Done")` and a title from
  `primary + extra` still fit a `button(_ title: String)` helper. An argument
  that cannot be an `Int` — a `String`, a name bound to one, an enum case or constant such as
  `A11y.increment` or `AccessibilityID.Counter.increment`, an enum's `rawValue` unless the file
  declares the enum with an integer raw type — is not an index either, so a helper declared in
  another file is not reported.

### Non-Violating Examples

```swift
// Find by identifier, then one cast: the shape this rule recommends.
let count = try sut.inspect().find(viewWithAccessibilityIdentifier: "count").text().string()

// Searches by text and by type.
try sut.inspect().find(button: "+1").tap()
let icon = try sut.inspect().find(ViewType.Image.self) { try $0.actualImage().name() == "gear" }

// A finder helper wrapping the search, so the test reads in the app's terms.
private extension InspectableView {
    func count() throws -> String {
        try find(viewWithAccessibilityIdentifier: "count").text().string()
    }
}

// ForEach rows are data.
let third = try sut.inspect().find(ViewType.ForEach.self).view(RowView.self, 2)
```

### Violating Examples

```swift
// Before: three positional steps
func testIncrement() throws {
    let sut = CounterView()
    try sut.inspect().vStack().hStack(1).button(0).tap()
}

// After: tag the button in production code…
Button("+1") { count += 1 }
    .accessibilityIdentifier("increment")

// …and search for it
func testIncrement() throws {
    let sut = CounterView()
    try sut.inspect().find(viewWithAccessibilityIdentifier: "increment").button().tap()
}
```

```swift
// Climbing from a label to its row, then taking the first button found there
let label = try sut.inspect().find(text: "Workspace")
try label.parent().parent().find(ViewType.Button.self).tap()

// Instead: search for the container that holds the text
try sut.inspect().find(ViewType.HStack.self, containing: "Workspace")
    .find(ViewType.Button.self).tap()
```

### Choosing the search

Accessibility identifiers are the most stable choice. They change only when someone changes
them on purpose, VoiceOver does not read them, and they are often already in place for XCUITest.
When one is not available, `find(button:)`, `find(text:)`, `find(MyRow.self)` and
`find(ViewType.X.self, where:)` all survive reordering and wrapping. Wrapping each search in a
small `private extension InspectableView` helper keeps the identifier string in one place, and
lets a test say `sut.inspect().count()` rather than spelling out the plumbing.

Searching is not immune to everything. When a new SDK changes a view's internal representation,
ViewInspector has to learn the new shape before `find` can see through it. The iOS 27 lazy stacks
were an example. That kind of failure is the library's to fix, not something each test has to
repair.

### When the position is the point

Sometimes the order is what the test checks: that the tabs appear in a given order, or that a
leading `Spacer` right-aligns a chat bubble. A search cannot express that, so the walk is the
right tool and the finding should be suppressed where it stands:

```swift
// Tab order is the behaviour under test.
// swiftprojectlint:disable:next positional-view-lookup
_ = try tabs.view(GeneralPane.self, 0)
```

A typed lookup like `view(GeneralPane.self, 0)` at least fails loudly on a reorder instead of
checking the wrong pane, which is the shape to prefer when order is the subject.

### Discussion

ViewInspector's own guide teaches the chain first and presents `find` as an alternative, so this
rule takes a position beyond the library's documentation. The evidence for that position is the
library's commit history above and Jon Reid's argument, credited at the top of this page.

**Measured.** Over the ViewInspector tests in 11 repositories (165 files), nine of the author's
plus two of Jon Reid's held out (TestableView and Mastermind), the rule reports 47 lookups. Each
was read by hand against its source: 43 are walks that a layout change would break or retarget.
The other 4 deliberately assert order (three tabs in one test, a leading `Spacer` in another) and
want the suppression above. The repositories whose tests already search, including
SwiftLintRuleStudioTeam, SwiftFormatRuleStudio and TestableView, report nothing. 34 of the 47 sit
on a line with no `inspect()` call, mostly a walk continued through a local, a `parent()` climb
inside a finder helper, or a view handed to a `map { }` closure, which is why the rule follows
bindings rather than matching one expression at a time. When the rule was written the count was
67: the other 20 were walks in this repository's own `Tests/AppTests`, which now search by
accessibility identifier instead.

On ViewInspector's own test suite the rule reports 362 lookups. Those are expected: the library
tests its accessors by walking to them on purpose, mostly through SwiftUI views it builds inline
in the test. On an older copy of the suite (333 lookups) every one was checked against its source
and ViewInspector's API, and each is a real positional step: 330 are reported because a SwiftUI
view built inline is not test-owned, and 3 because of the `didAppear` gap under Known Limitations.
Across the 86 repositories of a held-out corpus (48,307 Swift files outside `.build/`, including
GRDB, IceCubesApp, The Composable Architecture, swift-nio and the swift compiler's own tree), the
rule reports 334 lookups: the older copy's 333 and Mastermind's one walk, nothing else. The compiler's
tree is 23,845 of those files and reports none. That figure covers the whole corpus since
SwiftProjectLint `5b83f22f` (SEI `f34cee3`), the first build that finished the compiler's tree: 63 s,
where earlier runs passed an hour. Every run before covered the other 85, and their output is
byte-identical at `8257d6a9` (SEI `cfbb250`) and at `5b83f22f` (re-run 2026-10-14, release CLI,
`--format json`, an empty config).

*Note, 2026-10-17:* the figures above predate reporting an index of 0, `[0]` and `.first` on a
custom view or modifier, and counting `navigationBarItems()` on a container as a level. They
have not been re-measured since.

### Known Limitations

- **The step into a `ForEach` is positional.** `list().forEach(0)` is reported even when the
  `ForEach` is the list's only child, because the index counts the list's children. Reach rows
  with `find(ViewType.ForEach.self)` instead, after which a row index is not reported.
- **A `find` predicate is not read.** Its parameter is a candidate under test, not an inspected
  root. The parameter of a closure iterating views — `findAll(…).map { $0.… }`,
  `stack.forEach { child in … }` — is followed.
- **`inspect` is recognised by its shape.** In a file that imports ViewInspector, any
  `x.inspect()` without arguments, or `x.inspect { item in … }`, is read as ViewInspector's.
- **Bindings are resolved lexically.** A local reassigned after its declaration is read from its
  declaration. Ternaries, `??`, `enumerated()` tuples, collection operations such as
  `dropFirst()` and `reversed()`, typealiases, and properties inherited from a superclass are not
  followed. A closure's parameter takes no type from a property it is assigned to: in
  `sut.didAppear = { view in … }` the view's type is unknown, so a walk inside a test-declared
  view reached that way is reported. `sut.on(\.didAppear) { view in … }` is followed.
- **A test-owned subject is recognised by its type name.** A fixture whose type is declared in
  another file is not recognised. A method called on a test-declared view is read as a modifier,
  so a factory method on one (`ProbeHost().makeScreen()`) counts as test-owned too. A factory is
  read from its declared return type, looking first in the types around the call. A SwiftUI view
  built inline in the test (`HStack { Text("a"); Text("b") }`) is not test-owned: its content can
  be an app view, and nothing in the chain says when the walk enters it.
- **A host's app views are found by constructor.** A test-declared view counts as building an
  app view when a statement in its `body`, or in a member typed `some View`, constructs a type that
  is neither SwiftUI's nor declared in the file — directly, or handed to `AnyView(…)`, `overlay(…)`,
  `background(…)` or `mask(…)`. Action closures (`Button`'s, `onAppear`, `task`) build nothing. An
  app view returned by a function call (`makeEditor()`), or passed in where the host is built
  (`Wrapper(content: AppEditor())`, a stateful preview wrapper), is not seen, so the host keeps its
  ownership through searches. Two views of the same name in one file count as a host only when
  each builds an app view.
- **Styles and modifiers declared elsewhere are read by name.** `inspect()` on a type whose name
  ends in `Style` is read as a style, which is inspected as itself, and on one ending in
  `Modifier` as a modifier, whose children are the views its `body(content:)` builds. A modifier
  declared in another file under any other name is misread, and an index of 0 into its body is
  not reported. One named like a style (`CardStyle: ViewModifier`) is read as itself, so its body
  also loses a level and a two-step walk into it goes unreported. One named like a view
  (`Shimmer: ViewModifier`) is read as an app view, whose `inspect()` resolves `text(0)` as
  `text()`. So `CardStyle().inspect().text(0)` and `Shimmer().inspect().text(0)` are not
  reported, while `ShimmerModifier().inspect().text(0)` is. `modifier(Shimmer.self)` and a
  parameter typed `InspectableView<ViewType.ViewModifier<Shimmer>>` name a modifier whatever it
  is called, so an index after either is reported.
- **An index after a named slot is reported.** `labelView().text(0)`, `header().text(0)` and
  `sheet().text(0)` pick the first of the views a `@ViewBuilder` made, and `toolbar().item(0)` the
  first of the toolbar's items. When the slot holds one view, write `text()`, or `item()` for a
  toolbar's only item.
- **An index of 0 on a custom view is reported even when its body is one view.** When
  `TitleView`'s body is a single `Text`, `find(TitleView.self).text(0)` reaches the same view as
  `text()`. The rule reads one test file at a time and does not see the bodies of the app's views,
  so it cannot tell that body from one of several top-level views, where `text(0)` silently takes
  the first. Write `text()`, which fails loudly if the body gains a second view. The same holds
  for a modifier's `body(content:)`, wherever the rule knows it is a modifier (see the bullet on
  names above). A view the test file declares is test-owned, so nothing in its layout is
  reported either way. A bare `inspect()` is the opposite case: `inspect().text()` and
  `inspect().text(0)` are not reported, and on a body of several views both take the first. So
  is a custom row reached by a subscript, `.first` or iteration over a `ForEach`.
- **A step without an index that takes the first child is not reported as a pick.**
  `toolbar().item()`, `itemGroup()`, `navigationBarItems()` on a container, and `x()` on a
  `NavigationView`, `NavigationStack`, `NavigationSplitView`, `NavigationLink`, `ControlGroup` or
  navigation destination take the first of several children, as an index of 0 would. The rule
  cannot count the children, and with one child the step only asserts its type, so only the
  indexed forms are reported as picks. `x()` on those containers reaches a child of the receiver,
  so the step counts as a level, as `vStack()` does: `inspect().navigationStack().vStack()` is
  reported as a second step. So is `inspect().navigationView().navigationBarItems().list()`:
  despite its name, `navigationBarItems()` never reaches the bar items. It strips the wrapper
  `.navigationBarItems(…)` put around the receiver's child and returns the view the modifier was
  applied to, which on a container is its first child, one level down. On a found view, a slot or
  a bare `inspect()` that child is the receiver itself, so there the step unwraps in place and
  starts a new anchor. `item()` and `itemGroup()` start a new anchor too, as the `toolbar()` they
  are read from does: an item is the toolbar's content, not a level of layout.
  `toolbar().item().text()` is not reported, and the item's own views are counted from it, so
  `toolbar().item().vStack().text()` is a second step.
- **`#if` branches.** A local declared differently in each branch of an `#if` is read from the
  first branch.
- **Very long chains are not read.** A chain of more than 64 links, or about 30 locals each built
  from the last, is skipped.

### Companion

[ViewHosting Before Inspection](view-hosting-before-inspection.md) and
[Observable Environment View Missing Inspection Hook](observable-environment-view-missing-inspection-hook.md)
cover the other ViewInspector hazard this project knows about: a view that traps when inspected
out of the tree.

---
