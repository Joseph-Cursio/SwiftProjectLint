import SwiftSyntax

/// The call-side half of the composition-root gate: which calls *use* an instant passed to them,
/// and which only convert it.
///
/// In its own file because the placement extension is at its length limit, and because it reads as
/// one decision with its lists.
extension NonInjectedNondeterminismVisitor {

    /// True when `call` relates its arguments to one another, or derives a fact from an instant,
    /// rather than taking a value as a parameter: the argument-side mirror of a combining receiver.
    ///
    /// `Date().timeIntervalSince(start)` was refused as a receiver from the start, and
    /// `start.timeIntervalSince(Date())` is the same elapsed time with the operands swapped. The
    /// argument gate looked only at *where* the read sat, so the second spelling, and the
    /// benchmark's other common one, were both labelled composition roots:
    ///
    /// ```swift
    /// let t0 = Date(); work(); let t1 = Date()
    /// return DateInterval(start: t0, end: t1).duration   // both reads: "nothing to inject"
    /// formatter.localizedString(for: date, relativeTo: Date())
    /// ```
    ///
    /// **Over-matching is the safe direction here, so the set is generous.** It is the reverse of
    /// `restatingMembers`: a name listed here moves a site back to the ordinary message, which is
    /// what every site got before the arm existed, so a project function that happens to share a
    /// name costs a sentence and nothing else. A name *missing* from here is what leaks, which is
    /// why the set reaches past the three shapes the corpus showed into the rest of `Date`,
    /// `Calendar` and `TimeZone`. It is still a list: a project's own combiner with an unlabelled
    /// argument (`secondsSince(Date())`) leaks, and the cost is the message.
    ///
    /// Four ways in, any one enough:
    /// - a label that names a second operand (`since:`, `relativeTo:`);
    /// - a pair of labels that bound a span (`from:`/`to:`, `start:`/`end:`, `start:`/`duration:`),
    ///   which is also what catches an initializer spelled `.init(start:end:)`, whose type is not
    ///   in the syntax at all;
    /// - the callee's name, where `DateInterval.init(…)` is named by its type rather than `init`;
    /// - a path append, which composes a name; see below.
    ///
    /// ## Composing a path name is a use
    ///
    /// The same filename used to land in different arms depending on how it was spelled:
    ///
    /// ```swift
    /// directory.appendingPathComponent(UUID().uuidString)          // "handed straight on"
    /// parent.appendingPathComponent("x-\(UUID().uuidString)")      // the ordinary message
    /// ```
    ///
    /// Both build a new value out of the read and a value this scope supplied, the receiver, and
    /// the path is then created, stored or returned here. That is the receiver-side refusal
    /// (`Date().addingTimeInterval(timeout)`) seen from the argument: nothing downstream takes the
    /// name as a parameter that a test could pin, because this scope is where the name is made.
    /// The ordinary message already lists "a name" among the decisions worth a seam, so the
    /// interpolated spelling had it right and the bare one moves to match. A scratch path that
    /// does not outlive the call is declined before this is asked; see `isScratchDirectoryName`.
    static func combines(_ call: FunctionCallExprSyntax) -> Bool {
        let labels = Set(call.arguments.compactMap { $0.label?.text })
        if !labels.isDisjoint(with: combiningLabels) { return true }
        if combiningLabelPairs.contains(where: labels.isSuperset(of:)) { return true }
        if appendsToAPath(call) { return true }
        return calleeName(of: call).map(combiningCallees.contains) ?? false
    }

    /// The name a call is known by: a function's name, a method's, or for an initializer the type's.
    ///
    /// `DateInterval.init(start:end:)` is spelled with a member named `init`, so reading the member
    /// name alone made the explicit initializer a different callee from `DateInterval(start:end:)`.
    /// An implicit `.init(…)` names no type and answers `nil`.
    static func calleeName(of call: FunctionCallExprSyntax) -> String? {
        let callee = call.calledExpression.as(GenericSpecializationExprSyntax.self)?.expression
            ?? call.calledExpression
        if let reference = callee.as(DeclReferenceExprSyntax.self) {
            return reference.baseName.text
        }
        guard let member = callee.as(MemberAccessExprSyntax.self) else { return nil }
        guard member.declName.baseName.tokenKind == .keyword(.`init`) else {
            return member.declName.baseName.text
        }
        if let base = member.base?.as(DeclReferenceExprSyntax.self) { return base.baseName.text }
        return member.base?.as(MemberAccessExprSyntax.self)?.declName.baseName.text   // Foundation.T.init
    }

    /// True when `call` is a numeric or string conversion of its one argument: `Int(x)`,
    /// `Double(x)`, `String(describing: x)`.
    ///
    /// A conversion re-presents a value the way `.timeIntervalSince1970` does, so the gate steps
    /// through it rather than treating it as the call the value was handed to. Treating it as a
    /// hand-off was a leak in the dangerous direction:
    ///
    /// ```swift
    /// Int(Date().timeIntervalSince1970) - last > 300   // a TTL check, labelled "nothing to inject"
    /// ```
    ///
    /// The read sat in `Int`'s argument list, so the arithmetic around the conversion was never
    /// seen. Stepping through, the question is asked of `Int(…)` itself: an operand here, a
    /// hand-off in `bind(Int(Date().timeIntervalSince1970), at: 1)`.
    static func isConversion(_ call: FunctionCallExprSyntax) -> Bool {
        guard call.arguments.count == 1,
              call.trailingClosure == nil,
              let argument = call.arguments.first,
              argument.label == nil || argument.label?.text == "describing",
              let type = call.calledExpression.as(DeclReferenceExprSyntax.self)?.baseName.text
        else { return false }
        return conversionTypes.contains(type)
    }

    /// The conversion call (`Int(…)`, `String(describing: …)`) whose only argument is `node`.
    func enclosingConversion(of node: Syntax) -> FunctionCallExprSyntax? {
        guard let element = node.parent?.as(LabeledExprSyntax.self),
              let call = element.parent?.parent?.as(FunctionCallExprSyntax.self),
              Self.isConversion(call) else { return nil }
        return call
    }

    /// Callees that relate two values or read a calendar or time-zone fact out of an instant.
    ///
    /// - Two operands: `timeIntervalSince`, `distance`, `compare`, `max`, `min`, `contains`,
    ///   `DateInterval`, `stride`.
    /// - A fact derived from the instant through a calendar: `component`, `dateComponents`,
    ///   `startOfDay`, `dateInterval`, `range`, `ordinality`, the `isDate…` family, the
    ///   `next…` searches, and `date(byAdding:…)` / `date(bySetting…)`, which are deadlines spelled
    ///   through `Calendar`.
    /// - A fact derived from the instant through a time zone: its offset, its daylight-saving
    ///   state, its abbreviation then, and the next transition.
    private static let combiningCallees: Set<String> = [
        "timeIntervalSince", "distance", "compare", "max", "min", "contains", "DateInterval",
        "stride",
        "component", "components", "dateComponents", "startOfDay", "dateInterval", "date",
        "range", "ordinality",
        "isDate", "isDateInToday", "isDateInYesterday", "isDateInTomorrow", "isDateInWeekend",
        "nextDate", "enumerateDates", "nextWeekend",
        "secondsFromGMT", "isDaylightSavingTime", "daylightSavingTimeOffset", "abbreviation",
        "nextDaylightSavingTimeTransition",
    ]

    /// Argument labels that name a second operand: `Date(timeInterval: 60, since: Date())` is a
    /// deadline, `localizedString(for: d, relativeTo: Date())` an elapsed time as text.
    private static let combiningLabels: Set<String> = ["since", "relativeTo"]

    /// Label pairs that bound a span between two values.
    private static let combiningLabelPairs: [Set<String>] = [
        ["from", "to"], ["start", "end"], ["start", "duration"],
    ]

    /// Types whose single-argument initializer converts rather than combines.
    private static let conversionTypes: Set<String> = [
        "Int", "Int64", "Int32", "UInt", "UInt64", "UInt32", "Double", "Float", "CGFloat",
        "TimeInterval", "String", "Decimal",
    ]
}
