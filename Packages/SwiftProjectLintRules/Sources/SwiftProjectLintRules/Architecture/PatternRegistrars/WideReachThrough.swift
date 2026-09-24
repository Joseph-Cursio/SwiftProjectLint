import SwiftProjectLintModels
import SwiftProjectLintRegistry
import SwiftProjectLintVisitors

/// A registrar for the wide-reach-through pattern: one file reaching into a single collaborator
/// for many of its members, which is the Law of Demeter measured by width instead of depth.
struct WideReachThrough: PatternRegistrarProtocol {

    var pattern: SyntaxPattern {
        SyntaxPattern(
            name: .wideReachThrough,
            visitor: WideReachThroughVisitor.self,
            severity: .info,
            category: .architecture,
            messageTemplate: "This file reads many different members of one collaborator",
            suggestion: "Move the logic that needs these members onto the collaborator, or pass "
                + "the specific values this file needs.",
            description: "Detects a file that reaches through one object for several of its "
                + "members, meaning it has internalised that object's shape and a change to it "
                + "ripples outward. Unlike the depth-based Law of Demeter rule this catches "
                + "ordinary two-dot chains, which is where the widest reach-throughs are found. "
                + "Reaching repeatedly for a single member is not reported — that is a missing "
                + "forwarding accessor, not a design problem — and a member set that recurs "
                + "identically across several files is treated as an idiom rather than a fault."
        )
    }
}
