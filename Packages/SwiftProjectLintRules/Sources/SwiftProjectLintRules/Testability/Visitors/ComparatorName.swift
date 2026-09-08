import SwiftSyntax

/// Derives a name for a comparator closure from the keys it compares.
///
/// The rule has always known a closure is a comparator — it reads that off the
/// call it is passed to, `sorted` / `min` / `max` / `partition`. What it could
/// not say is *which* comparator, so the finding asked a reader to invent a name
/// for every one of them. On a corpus with 82, that is the whole cost of acting.
///
/// The name is a function of the compared key paths and their operators:
///
/// ```swift
/// if lhs.location != rhs.location { return lhs.location < rhs.location }
/// return lhs.typeName < rhs.typeName          // → byLocationThenTypeName
///
/// lhs.total != rhs.total ? lhs.total > rhs.total : lhs.template < rhs.template
///                                             // → byTotalDescendingThenTemplate
///
/// ($0.name, $0.parameterCount) < ($1.name, $1.parameterCount)
///                                             // → byNameThenParameterCount
/// ```
///
/// The third spelling is worth calling out: Swift's tuple `<` is lexicographic,
/// so a tuple comparison *is* a multi-key comparator written as one expression.
/// It carries no `!=` guard and no `&&`, so a search for either shape misses it
/// entirely — on the corpus this was measured against, 14 comparators were
/// spelled that way.
///
/// **Deliberately silent rather than wrong.** A derived name is only worth
/// printing when it describes the whole comparator, so anything this cannot
/// account for — a key reached through a call or a subscript, a third clause it
/// did not recognise —
/// returns `nil` and the finding falls back to its existing wording. A suggestion
/// a reader has to check is worse than none, because checking it costs what
/// inventing the name would have.
///
/// **A single-key ascending comparator returns `nil` too**, and that is not a
/// limitation. `$0.key < $1.key` inherits irreflexivity, asymmetry and
/// transitivity from the field's own `Comparable` conformance and cannot violate
/// them, and `ascendingByKey` says nothing the four-token closure did not. The
/// names worth writing belong to exactly the comparators whose laws are worth
/// checking: the multi-key ones, where a tiebreak exists and incomparability is
/// reachable.
enum ComparatorName {

    /// A single ordering clause: the key path compared, and which way.
    private struct Key {
        /// Dotted, because a key is often nested — `identity.normalized`, not
        /// `normalized`. The last component alone would collide across the two
        /// `identity.normalized` / `entry.identityHash` comparators that sit in
        /// the same corpus, and would name the key by less than the code reads.
        let property: String
        let descending: Bool
        /// Source offset, because the name is order-sensitive —
        /// `byLocationThenTypeName` and `byTypeNameThenLocation` are different
        /// comparators — and a syntax walk does not visit in source order. A
        /// ternary's branches are reached after the sequence that contains them.
        let position: Int
    }

    /// The suggested name, or `nil` when the body is not a shape this can
    /// account for in full.
    static func derived(from closure: ClosureExprSyntax) -> String? {
        guard let (lhs, rhs) = parameterNames(of: closure) else { return nil }
        let keys = clauses(in: closure, lhs: lhs, rhs: rhs)
        guard keys.count >= 2 else { return nil }
        var name = "by"
        for (index, key) in keys.enumerated() {
            if index > 0 { name += "Then" }
            name += key.property.split(separator: ".")
                .map { $0.prefix(1).uppercased() + $0.dropFirst() }
                .joined()
            if key.descending { name += "Descending" }
        }
        return name
    }

    /// `{ lhs, rhs in … }` — both parameters must be named for the body to be
    /// readable at all. A shorthand `$0` / `$1` body is handled by treating those
    /// as the two names.
    private static func parameterNames(of closure: ClosureExprSyntax) -> (String, String)? {
        guard let signature = closure.signature else { return ("$0", "$1") }
        guard case let .simpleInput(parameters)? = signature.parameterClause,
              parameters.count == 2 else { return nil }
        let names = parameters.map { $0.name.text }
        return (names[0], names[1])
    }

    /// Every `lhs.x < rhs.x` style comparison in the body, in source order.
    ///
    /// Order matters and is the reason this walks statements rather than
    /// collecting matches: `byLocationThenTypeName` and `byTypeNameThenLocation`
    /// are different comparators.
    private static func clauses(
        in closure: ClosureExprSyntax, lhs: String, rhs: String
    ) -> [Key] {
        var keys: [Key] = []
        var seen: Set<String> = []
        let collector = ComparisonCollector(lhs: lhs, rhs: rhs, viewMode: .sourceAccurate)
        collector.walk(closure.statements)
        guard collector.isAccountedFor else { return [] }
        for key in collector.keys.sorted(by: { $0.position < $1.position })
            where !seen.contains(key.property) {
            seen.insert(key.property)
            keys.append(key)
        }
        return keys
    }

    /// Walks a comparator body collecting `lhs.p <op> rhs.p` comparisons.
    ///
    /// `isAccountedFor` is the honesty check: any binary operator it does not
    /// recognise, or a comparison whose two sides are not the same property on
    /// the two parameters, means the derived name would describe less than the
    /// comparator does — so nothing is suggested.
    private final class ComparisonCollector: SyntaxVisitor {
        private let lhs: String
        private let rhs: String
        fileprivate var keys: [Key] = []
        fileprivate var isAccountedFor = true

        init(lhs: String, rhs: String, viewMode: SyntaxTreeViewMode) {
            self.lhs = lhs
            self.rhs = rhs
            super.init(viewMode: viewMode)
        }

        override func visit(_ node: InfixOperatorExprSyntax) -> SyntaxVisitorContinueKind {
            record(left: node.leftOperand, op: node.operator, right: node.rightOperand)
            return .visitChildren
        }

        override func visit(_ node: SequenceExprSyntax) -> SyntaxVisitorContinueKind {
            // An unfolded tree — what `Parser.parse` produces, and what every
            // visitor here walks — spells `a < b` as a flat element list rather
            // than an `InfixOperatorExpr`. A ternary flattens into the same list
            // alongside its condition, so this scans for operator triples instead
            // of assuming the sequence is one comparison.
            let elements = Array(node.elements)
            for index in elements.indices where index > 0 && index + 1 < elements.count {
                guard elements[index].is(BinaryOperatorExprSyntax.self) else { continue }
                record(left: elements[index - 1], op: elements[index], right: elements[index + 1])
            }
            return .visitChildren
        }

        private func record(left: ExprSyntax, op: ExprSyntax, right: ExprSyntax) {
            guard let symbol = op.as(BinaryOperatorExprSyntax.self)?.operator.text else { return }
            switch symbol {
            case "<", ">":
                guard let resolved = resolve(left, right) else {
                    isAccountedFor = false
                    return
                }
                let descending = symbol == ">"
                for key in resolved {
                    // A swapped element reverses the operator for that key alone,
                    // which is the whole reason direction is resolved per element
                    // rather than read off the operator once.
                    keys.append(Key(property: key.path,
                                    descending: descending != key.isSwapped,
                                    position: key.position))
                }

            case "!=", "==":
                // The guard half of a tiebreak — carries no ordering of its own,
                // but still has to be readable, or the name would describe less
                // than the comparator does.
                if resolve(left, right) == nil { isAccountedFor = false }

            default:
                isAccountedFor = false
            }
        }

        /// One key recovered from a comparison, before its direction is known.
        private struct Resolved {
            let path: String
            /// The two sides were written in the opposite order — see `keyPair`.
            let isSwapped: Bool
            let position: Int
        }

        /// The keys a single comparison orders by: one for `lhs.p < rhs.p`, and
        /// as many as the tuple is wide for `(lhs.a, lhs.b) < (rhs.a, rhs.b)`.
        ///
        /// Swift's tuple `<` is lexicographic, which makes it a complete multi-key
        /// comparator written as one expression — the idiomatic spelling, and one
        /// a search for `!=` tiebreaks or `&&` chains never sees. `nil` when any
        /// element fails to resolve, because a name that covers some of a tuple
        /// covers none of the comparator.
        private func resolve(_ left: ExprSyntax, _ right: ExprSyntax) -> [Resolved]? {
            guard let leftTuple = left.as(TupleExprSyntax.self),
                  let rightTuple = right.as(TupleExprSyntax.self) else {
                return keyPair(left, right).map { [$0] }
            }
            let leftElements = Array(leftTuple.elements)
            let rightElements = Array(rightTuple.elements)
            guard leftElements.count == rightElements.count else { return nil }
            var resolved: [Resolved] = []
            for (leftElement, rightElement) in zip(leftElements, rightElements) {
                guard let key = keyPair(leftElement.expression, rightElement.expression) else {
                    return nil
                }
                resolved.append(key)
            }
            return resolved
        }

        /// `lhs.p` against `rhs.p` for the same key path `p`, in either order.
        ///
        /// The swapped order is a real idiom rather than a mistake. This, from the
        /// corpus, orders by value **descending** and then by key **ascending**,
        /// using a single `>`:
        ///
        /// ```swift
        /// rows.sorted(by: { ($0.value, $1.key) > ($1.value, $0.key) })
        /// ```
        ///
        /// Only the second element is swapped, so direction cannot be taken from
        /// the operator and applied to the tuple as a whole. Reading it that way
        /// yields `byValueDescendingThenKeyDescending` — a confident, wrong name,
        /// which costs a reader more than no name at all.
        private func keyPair(_ left: ExprSyntax, _ right: ExprSyntax) -> Resolved? {
            let position = left.position.utf8Offset
            if let leftPath = path(of: left, rootedAt: lhs),
               let rightPath = path(of: right, rootedAt: rhs),
               leftPath == rightPath {
                return Resolved(path: leftPath.joined(separator: "."),
                                isSwapped: false, position: position)
            }
            if let leftPath = path(of: left, rootedAt: rhs),
               let rightPath = path(of: right, rootedAt: lhs),
               leftPath == rightPath {
                return Resolved(path: leftPath.joined(separator: "."),
                                isSwapped: true, position: position)
            }
            return nil
        }

        /// The member chain from a parameter: `lhs.identity.normalized` reads as
        /// `["identity", "normalized"]`. `nil` when the expression is anything
        /// else — a call, a subscript, a literal, or a chain off some other root.
        ///
        /// A tuple position is refused even though it orders perfectly well.
        /// `lhs.1.timestamp < rhs.1.timestamp` is a valid key, but `by1Timestamp`
        /// is not a name anyone would have written, and a bad name costs a reader
        /// what inventing a good one would have. Silence is the better answer.
        private func path(of expr: ExprSyntax, rootedAt parameter: String) -> [String]? {
            var components: [String] = []
            var current = expr
            while let access = current.as(MemberAccessExprSyntax.self) {
                let component = access.declName.baseName.text
                guard let initial = component.first, !initial.isNumber else { return nil }
                components.insert(component, at: 0)
                guard let base = access.base else { return nil }
                current = base
            }
            guard current.trimmedDescription == parameter, !components.isEmpty else { return nil }
            return components
        }
    }
}
