/// Name fragments that mark a type as a test double.
///
/// A double is already the substitute an injection would supply, so no architecture rule
/// should ask for a seam in front of one: naming `MockClient` as a concrete dependency, or
/// its construction as a hard-wire, tells the author to abstract the abstraction.
///
/// This is the single source of truth for that vocabulary, in the same way and for the same
/// reason as `ServiceTypeSuffix`. It began as a private array inside
/// `ConcreteTypeUsageVisitor` and `DirectInstantiation` — the rule that counts the same seam
/// from the construction end — never had it, so `MockGenerator(…)` was exempt when it was
/// *declared* and reported when it was *built*.
enum MockTypeName {

    private static let fragments = ["Mock", "Stub", "Fake", "Spy", "Dummy"]

    /// Whether `name` reads as a test double.
    ///
    /// Matched anywhere in the name rather than as a prefix: the projects here write both
    /// `MockGenerator` and `InMemoryFakeStore`.
    static func matches(_ name: String) -> Bool {
        fragments.contains { name.contains($0) }
    }
}
