import SwiftSyntax

/// The names and operators the Actor Reentrancy rule reads as a write to the property it guarded on.
extension ActorReentrancyVisitor {

    /// Standard-library mutating method names recognised as writes to a stored property
    /// when called on it as a receiver. Kept as a allowlist so that non-mutating reads
    /// (`processedIDs.contains(id)`, `X.isEmpty`, `X.count`) are not mistaken for writes.
    /// Project-declared `mutating func`s join it in `mutatingMethodNames(visibleFrom:)`.
    static let standardLibraryMutatingMethods: Set<String> = [
        // Set / Array / OrderedSet
        "insert", "append", "add", "update", "updateValue",
        // Removal (still counts as state change between check and await)
        "remove", "removeAll", "removeFirst", "removeLast", "removeValue",
        "popLast", "popFirst",
        // Set-algebra mutation
        "formUnion", "formIntersection", "subtract", "formSymmetricDifference",
        // Dictionary-style merge
        "merge", "replace"
    ]

    /// Compound-assignment operator tokens recognised as writes. Plain `=` is
    /// an AssignmentExprSyntax node (not a BinaryOperatorExprSyntax), so it
    /// is handled separately in `isAssignmentOperator(_:)`.
    ///
    /// Kept as an explicit allowlist rather than an "ends-in-`=`" heuristic so
    /// that comparison operators (`==`, `!=`, `<=`, `>=`, `===`, `!==`) and
    /// hypothetical user-defined operators ending in `=` cannot be mistaken
    /// for writes.
    private static let compoundAssignmentOperators: Set<String> = [
        "+=", "-=", "*=", "/=", "%=",
        "<<=", ">>=",
        "&=", "|=", "^=",
        "&+=", "&-=", "&*=",
        "&<<=", "&>>="
    ]

    /// True when `element` is the operator slot of a SequenceExpr representing
    /// an assignment to the LHS. Covers plain `=` (an AssignmentExprSyntax
    /// node) and compound-assignment operators (a BinaryOperatorExprSyntax
    /// whose token text is in `compoundAssignmentOperators`).
    static func isAssignmentOperator(_ element: ExprSyntax) -> Bool {
        if element.is(AssignmentExprSyntax.self) { return true }
        if let binary = element.as(BinaryOperatorExprSyntax.self) {
            return compoundAssignmentOperators.contains(binary.operator.text)
        }
        return false
    }
}
