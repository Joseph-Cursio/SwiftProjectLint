[← Back to Rules](RULES.md)

## Layer Dependency

**Identifier:** `Layer Dependency`
**Category:** Architecture
**Severity:** Warning

### Rationale

In a single-target app, the layers are folders. No `import` marks one layer using another: `CheckoutViewModel` in `Presentation/` can use `CoreDataOrderStore` in `Persistence/` just by naming it, and nothing in the build notices.

[Architectural Boundary](architectural-boundary.md) can forbid the frameworks and named types a layer must avoid. But a deny list of project types goes out of date with every type someone adds. `may_depend_on` works the other way: it names the layers a layer *may* reference, and every reference into any other layer is reported.

### Configuration

Add `may_depend_on` to a layer in the same `architectural_layers` block that Architectural Boundary reads:

```yaml
architectural_layers:
  domain:
    paths: ["Domain/"]
    may_depend_on: []
  persistence:
    paths: ["Persistence/"]
    may_depend_on: ["domain"]
  presentation:
    paths: ["Presentation/"]
    may_depend_on: ["domain"]
```

- A layer may always reference its own types.
- `may_depend_on: []` lets a layer reference no other layer.
- A layer without `may_depend_on` is not checked by this rule.
- Files outside every layer, such as a composition root in `App/`, are never judged.

The CLI warns on stderr about configuration mistakes that would otherwise make a clean run look like a clean architecture:

- a layer path that matches no analysed file;
- a `may_depend_on` entry naming a layer that doesn't exist;
- layers that may depend on each other in a cycle, and so aren't really layered.

### Discussion

`LayerDependencyVisitor` is a cross-file rule. It records the top-level types (structs, classes, enums, actors, protocols and typealiases) declared in each layer's files. Then, in every layer that sets `may_depend_on`, it finds references to those names: type annotations, inheritance and extension clauses, and capitalised names in expressions such as `CoreDataOrderStore()` or `OrderStore.shared`.

Each type is reported once per file, at its first reference. A nested type is attributed through its outer type, so `CoreDataOrderStore.Request` counts as a reference to `CoreDataOrderStore`.

### Limitations

The rule reads syntax and does not resolve names, so it declines wherever a name is ambiguous:

- **A type name declared in more than one place**, whether in two layers or in a layer and an unlayered file, is not attributed to either.
- **A name the referencing file declares itself** at any depth, including as a generic parameter, is taken to mean that file's own type.
- **A member name after a dot**, such as `Route.CoreDataOrderStore`, is not a type reference.

References through type inference alone aren't seen. For example, `let store = makeStore()` references no type by name, so the rule reports nothing even if `makeStore()` returns a type from a forbidden layer.

### Non-Violating Examples

```swift
// Presentation/OrderRow.swift — presentation may depend on domain
struct OrderRow {
    let order: Order          // Domain/Order.swift
}

// App/Composition.swift — outside every layer, so wiring concrete types here is fine
let store: OrderStore = CoreDataOrderStore()
```

### Violating Examples

```swift
// Presentation/CheckoutViewModel.swift
final class CheckoutViewModel {
    let store: CoreDataOrderStore   // ← 'presentation' references 'CoreDataOrderStore' from 'persistence'
}
```

---
