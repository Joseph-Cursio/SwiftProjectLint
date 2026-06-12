[← Back to Rules](RULES.md)

## Unsafe Memory API

**Identifier:** `Unsafe Memory API`
**Category:** Memory Management
**Severity:** Info

### Rationale
Swift's raw-memory escape hatches — pointer types, `unsafeBitCast`/`unsafeDowncast`, the `withUnsafe…` buffer APIs, manual `bindMemory`/`assumingMemoryBound` rebinding, and `Unmanaged` reference juggling — opt out of the guarantees the rest of the language enforces: bounds checking, type safety, and ARC. A mistake in this code is **undefined behavior** rather than a compile error or a clean trap, and the failure often surfaces far from its cause. These APIs are genuinely necessary for C interop and tight performance work, so the goal isn't to forbid them — it's to keep every use visible, localized, and justified.

### Discussion
`UnsafeMemoryAPIVisitor` matches syntactically (no type resolution), so it errs toward surfacing rather than proving misuse:

- **Pointer / opaque types** in any position (parameter, property, return, generic argument): `UnsafePointer`, `UnsafeMutablePointer`, `Unsafe[Mutable]RawPointer`, `Unsafe[Mutable][Raw]BufferPointer`, `OpaquePointer`, `Unmanaged`.
- **Unsafe calls** by callee name, whether a free function or a method: `unsafeBitCast`, `unsafeDowncast`, `withUnsafePointer`, `withUnsafeMutablePointer`, `withUnsafeBytes`, `withUnsafeMutableBytes`, `withUnsafeTemporaryAllocation`, `assumingMemoryBound`, `bindMemory`, `withMemoryRebound`.
- **`Unmanaged` factories**: `Unmanaged.passRetained(…)`, `Unmanaged.fromOpaque(…)`, and the like.

The severity is **Info**: this is an audit signal. In interop or measured hot paths these uses are expected — confine them to the smallest region, comment the invariant being upheld, and prefer safe abstractions (`Array`, `Data`, `Span`) at the boundaries.

### Non-Violating Examples
```swift
struct Model {
    let values: [Int]
    func transform(_ input: String) -> Int { input.count }
}

// Ordinary casts and ARC-managed references are fine.
let maybe = value as? Int
let view = NSView()
```

### Violating Examples
```swift
let raw = unsafeBitCast(value, to: Int.self)         // unsafeBitCast
func f(_ ptr: UnsafeMutablePointer<Int>) { }         // pointer type
let typed = raw.assumingMemoryBound(to: UInt8.self)  // manual rebinding
data.withUnsafeBytes { buffer in use(buffer) }       // withUnsafe… API
let ref = Unmanaged.passRetained(object)             // Unmanaged factory
var handle: OpaquePointer?                            // C-interop handle
```

### See Also
- [Force Unwrap](force-unwrap.md) / [Force Try](force-try.md) — other safety escape hatches (crash-on-failure rather than undefined behavior).
