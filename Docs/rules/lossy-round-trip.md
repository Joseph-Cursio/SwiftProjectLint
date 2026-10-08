[← Back to Rules](RULES.md)

## Lossy Round Trip

**Identifier:** `Lossy Round Trip`
**Category:** Code Quality
**Severity:** Warning

### Rationale

A type that **takes a value apart** into storage and **puts it back together** must carry every field
across. When the rebuilding half hard-codes an empty value for a field, that field never survives, and
nothing says so:

```swift
func save(_ order: Order) async throws {
    record.setValue(order.identifier, forKey: "identifier")
    record.setValue(order.total.cents, forKey: "totalCents")
    record.setValue(order.paymentMethod.rawValue, forKey: "paymentMethod")
}

func recentOrders() async throws -> [Order] {
    …
    let identifier = record.value(forKey: "identifier") as? UUID
    …
    return Order(identifier: identifier, items: [], paymentMethod: method, discount: nil)
    //                                   ^^^^^^^^^                          ^^^^^^^^^^^^^
    //                    every order comes back with no line items and no discount
}
```

It compiles, and it satisfies every signature in the store's protocol. The in-memory test double every
suite has keeps whole `Order` values, so it round-trips everything and every test passes against it. The
app, running against the real store, loses data on every load.

`Lossy Struct Rebuild` cannot see this. That rule fires when a value is copied field-by-field from
another value of the **same** type. Here the order is built from a Core Data record.

### Why this earns a rule

This is the motivating bug from the Checkout sample, and it was not planted: the persistence code was
written to be minimal, and nobody noticed. A "reorder last" feature built on `recentOrders()` would
silently have produced an empty cart. The only check that caught it was a save-then-fetch property test
run against the real store, which is the right tool for the job but is a test someone has to think to
write.

Measuring the rule found a second instance of the same bug class, in a different shape. An edit form's
initialiser copied an existing value into its form fields and skipped one, and the save path rebuilt the
value with that field hard-coded to `[]`. Saving an edit wiped the field:

```swift
init(appState: AppState, editing: SkillDescriptor? = nil) {
    guard let editing else { return }
    id = editing.id
    name = editing.name
    …                                   // tier2AcceptableFor: never copied
}

private func buildDescriptor() -> SkillDescriptor {
    SkillDescriptor(id: id, name: name, …, tier2AcceptableFor: [], …)
}
```

### The fix

**Store every stored field, and read each one back.** For the Checkout store, that means persisting the
line items and the discount code:

```swift
func save(_ order: Order) async throws {
    let encodedItems = try JSONEncoder().encode(order.items)
    …
    record.setValue(encodedItems, forKey: "lineItems")
    record.setValue(order.discount?.value, forKey: "discountCode")
}

func recentOrders() async throws -> [Order] {
    …
    let items = try? JSONDecoder().decode([LineItem].self, from: encodedItems)
    let discount = (record.value(forKey: "discountCode") as? String).map(DiscountCode.init)
    return Order(identifier: identifier, items: items, paymentMethod: method, discount: discount)
}
```

**If a field is deliberately not persisted** (a cache, a transient UI flag), make that visible. A
reader cannot tell a choice from a mistake, and the rule cannot either. Suppress at the site with the
reason, or move the field out of the persisted type.

**Then pin it.** A save-then-load property test, `load(save(x)) == x` for generated values, run against
every conformer of the store protocol, catches this whole class at runtime, including the shapes this
rule cannot see.

### Discussion

`LossyRoundTripVisitor` pairs two members of one type: its body plus its extensions in the same file.

1. **A decomposition.** A member takes a parameter of a project-declared type `T` (or `T?`, or `[T]`
   walked in a `for` loop) and stores its fields in **slots**:
   - under a **key**, from an argument labelled like one (`setValue(_:forKey:)`, `set(_:forKey:)`,
     `encode(_:forKey:)`), or a subscript (`record["name"] = …`);
   - in a **property**: `self.name = draft.name`, a bare `name = draft.name`, or a mirrored
     `entity.name = draft.name`.

   A field passed through a local first (`let encoded = encode(order.items)`, then stored) still counts
   as stored.
2. **A rebuild.** Another member constructs `T(…)` and reads back **at least one of the same slots**:
   the same key, or the same property.
3. **The loss.** The rebuild passes an empty literal (`[]`, `[:]`, `nil`, `""`, `0`, `0.0`) for a
   labelled argument, alongside at least one argument that is not a constant.

The message separates the two ways a field is lost. **Never stored**: the decomposition does not write
it, so the rebuild had nothing to read. **Stored, then thrown away**: the decomposition writes it and
the rebuild ignores it. The second is the stronger claim: the data is on disk and the app pretends it
isn't.

#### Why the shared slot is required

Without it, any two members that mention one type look like a round trip:
`func select(_ order: Order) { selectedID = order.identifier }` beside
`func makeDraft() -> Order { Order(identifier: UUID(), items: []) }`. On the first measurement, with a
gate of "any member that reads a field off a `T` parameter", **21 of 23** production findings across
the author's repositories were that kind of noise: index constructors, placeholder rows, initial
reducer states.

#### Why the type must be declared in the project

`IndexPath(row: selectedIndex, section: 0)`, after storing `indexPath.row`, is a genuine round trip that
drops a field. It drops it on purpose, because the table has one section. On a 48,000-file held-out
corpus of third-party and tutorial code, all 14 findings before this gate were framework or dependency
types (`IndexPath`, `CGPoint`, XML element types), and all 14 were intended. With the gate, the corpus
reported nothing, while the rule recognised 86 complete round trips in it.

#### Measured precision

| corpus | files | round trips recognised | findings | true positives |
|---|---|---|---|---|
| the author's repositories | 9,818 | 8 | 2 | 2 |
| held-out third-party and tutorial code | 48,282 | 86 | 0 | — |

The evidence base for recall is small: two real bugs. The precision evidence is the more useful half.
Across 94 recognised round trips, the rule fired only where a field was actually being lost.

### Non-Violating Examples

```swift
// Every field comes back.
func recentOrders() throws -> [Order] {
    …
    return Order(identifier: identifier, items: items, paymentMethod: method, discount: discount)
}

// An in-memory store keeps WHOLE values. Nothing is taken apart, so nothing can be dropped.
func save(_ order: Order) { orders.append(order) }
func placeholder(for identifier: UUID) -> Order { Order(identifier: identifier, items: []) }

// A construction that reads none of the stored slots is not a rebuild.
func select(_ order: Order) { selectedID = order.identifier }
func makeDraft() -> Order { Order(identifier: UUID(), items: [], discount: nil) }

// A fallback made only of constants is a fresh value, not a rebuild.
guard let identifier = record.value(forKey: "identifier") as? UUID else {
    return Order(identifier: .zero, items: [], discount: nil)
}

// A type the project does not declare: the dropped field is the framework's business.
selectedIndex = indexPath.row
…
IndexPath(row: selectedIndex, section: 0)
```

### Violating Examples

```swift
// Never stored: `items` and `discount` are not written, and are rebuilt empty.
func save(_ order: Order) {
    record.setValue(order.identifier, forKey: "identifier")
}
func recentOrders() -> [Order] {
    records.map { Order(identifier: $0.value(forKey: "identifier"), items: [], discount: nil) }
}

// Stored, then thrown away: `discount` is on disk, and the load ignores it.
func save(_ order: Order) {
    defaults.set(order.identifier.uuidString, forKey: "identifier")
    defaults.set(order.discount?.value, forKey: "discount")
}
func load() -> Order? {
    guard let raw = defaults.string(forKey: "identifier"), let identifier = UUID(uuidString: raw) else {
        return nil
    }
    return Order(identifier: identifier, discount: nil)
}

// A record type mapping to and from the domain.
@Model final class OrderEntity {
    init(order: Order) {
        identifier = order.identifier
        method = order.paymentMethod.rawValue
    }
    var domain: Order {
        Order(identifier: identifier, items: [], paymentMethod: PaymentMethod(rawValue: method))
    }
}
```

### Known gaps

- **Both halves must be in one file.** A store whose save and load live in extensions in different
  files is not paired.
- **Only empty literals count.** `false`, `.none` and non-empty constants (`minSwiftVersion: "6.0"`) are
  left alone. They are as often a correct default as a lost field.
- **An omitted argument is not seen.** A rebuild that leaves a defaulted parameter out, rather than
  passing it empty, loses the field the same way. That is `Lossy Struct Rebuild`'s shape, from the
  persistence side.
- **Keys must be literal or constant.** A key built at runtime (`"item.\(index)"`) does not form a slot.

### Suppressing

If a field is deliberately not persisted, say so at the site, because the next reader cannot tell the
difference between a choice and a mistake:

```swift
// swiftprojectlint:disable lossy-round-trip
// Deliberate: `isSelected` is UI state and is never persisted.
```
