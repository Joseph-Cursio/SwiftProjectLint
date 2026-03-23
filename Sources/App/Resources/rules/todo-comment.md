[← Back to Rules](RULES.md)

## TODO Comment

**Identifier:** `TODO Comment`
**Category:** Code Quality
**Severity:** Info

### Rationale
TODO, FIXME, and HACK comments are markers for unresolved technical debt. They indicate work that was deferred and may be forgotten if not tracked in an issue tracker. Over time, these comments accumulate and obscure the codebase.

### Discussion
`TodoCommentVisitor` scans the leading trivia of every token for line comments (`//`) and block comments (`/* */`) that contain `TODO:`, `FIXME:`, or `HACK:` markers (case-insensitive). Parenthesized variants like `TODO(username):` are also detected.

Only one issue is reported per comment, even if multiple markers appear in the same comment.

### Non-Violating Examples
```swift
// This is a normal comment
let value = 42

// The todo list view shows all items
struct TodoListView: View { }

let todo = "item"
```

### Violating Examples
```swift
// TODO: fix this later
let value = 42

// FIXME: broken logic here
func calculate() -> Int { return 0 }

// HACK: workaround for compiler bug
let hack = true

/* TODO: refactor this entire module */
struct MyModule {}
```

---
