[← Back to Rules](RULES.md)

## Property Wrapper Naming Suffix

**Identifier:** `Property Wrapper Naming Suffix`
**Category:** Code Quality
**Severity:** Info

### Rationale
Property wrappers annotated with `@propertyWrapper` transform the behavior of the properties they decorate. A `Wrapper` suffix in the type name signals to readers that applying `@MyType` to a property will invoke the wrapper protocol rather than simply declaring a stored value of that type.

### Discussion
`NamingConventionVisitor` checks `struct` and `class` declarations that carry the `@propertyWrapper` attribute. If the type name does not end with `Wrapper`, an issue is reported. This rule applies to both struct and class property wrappers.

### Non-Violating Examples
```swift
@propertyWrapper
struct ClampedWrapper<Value: Comparable> {
    var wrappedValue: Value
}

@propertyWrapper
struct UserDefaultWrapper<Value> {
    var wrappedValue: Value
}
```

### Violating Examples
```swift
@propertyWrapper
struct Clamped<Value: Comparable> {  // missing "Wrapper" suffix
    var wrappedValue: Value
}

@propertyWrapper
class Observable<Value> {  // missing "Wrapper" suffix
    var wrappedValue: Value
    init(wrappedValue: Value) { self.wrappedValue = wrappedValue }
}
```

---
