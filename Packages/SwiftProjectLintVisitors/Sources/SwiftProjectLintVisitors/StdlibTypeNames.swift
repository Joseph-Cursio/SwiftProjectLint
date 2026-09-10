/// The stdlib and Foundation type names two rules both enumerate, in one place.
///
/// `CleanInstanceMethodCatalog.stdlibValueTypes` asks *"is a stored property of this type
/// data the test already supplies?"* and `PropertyTestCandidacy.equatableStdlibTypes` asks
/// *"can a test assert on a value of this type?"* Those are different questions with almost
/// the same answer, and each was answered from its own literal. The two had drifted five
/// entries in each direction.
///
/// One of those directions was a real gap: `Calendar`, `Locale`, `TimeZone`, `IndexSet` and
/// `IndexPath` are all `Equatable`, and a function returning one was refused as a
/// property-test candidate because the assertability list had never been told. The other
/// direction is a deliberate difference, and it is what `valueLeaves` and
/// `equatableContainers` are named for: a container is `Equatable` when its elements are, so
/// `Array` belongs to the assertability question and not to the "nominal leaves" one, which
/// recognises containers by syntax instead.
///
/// Found by dogfooding `ParallelListDrift` on this project.
enum StdlibTypeNames {

    /// Nominal leaves: a value a test constructs directly, and `Equatable` out of the box.
    static let valueLeaves: Set<String> = [
        "String", "Substring", "Character", "StaticString", "Bool",
        "Int", "Int8", "Int16", "Int32", "Int64",
        "UInt", "UInt8", "UInt16", "UInt32", "UInt64",
        "Double", "Float", "Float16", "CGFloat", "Decimal",
        "URL", "Data", "UUID", "Date", "TimeInterval",
        "Range", "ClosedRange",
        "IndexSet", "IndexPath", "Locale", "TimeZone", "Calendar"
    ]

    /// Generic containers, `Equatable` exactly when their elements are. Present for the
    /// assertability question and deliberately absent from `valueLeaves`, where containers,
    /// optionals and tuples are recognised by syntax rather than by name.
    static let equatableContainers: Set<String> = ["Array", "Set", "Dictionary"]

    /// Every stdlib name whose values a test can compare.
    static let equatable: Set<String> = valueLeaves.union(equatableContainers)
}
