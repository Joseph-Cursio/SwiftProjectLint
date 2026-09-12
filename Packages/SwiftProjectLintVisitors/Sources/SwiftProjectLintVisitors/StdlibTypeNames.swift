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

    /// The names above that are `struct`s or `enum`s — types whose `self` **is** the value.
    ///
    /// A third question, close enough to the other two to live here and different enough to be
    /// stated: *"when an `extension` names a type this project does not declare, is reading `self`
    /// a read of a value or a reach into a shared object?"* `PropertyTestCandidacy` asked it of
    /// `knownValueTypes`, which holds project declarations only, so every stdlib carrier answered
    /// "no" and a member reading bare `self` was refused (SwiftProjectLint#214).
    ///
    /// `Optional` is here and not above because it is not a *leaf* — its equatability is its
    /// wrapped type's — but it is an `enum`, which is the only thing this question asks.
    static let valueTypes: Set<String> = equatable.union(["Optional"])
}
