import SwiftSyntax

/// A project-wide pre-scan collecting the functions **this codebase declares**, by name.
///
/// ## Why a per-file visitor cannot answer this
///
/// The `Pure Closure Property-Test Candidate` rule reports a closure whose logic has no name. It
/// deliberately errs toward firing on **call-shaped** predicates, because the analyser cannot see
/// whether a call is total and the interesting predicates in real code are call-shaped — every
/// locale bug in `{ $0.name.localizedCaseInsensitiveContains(query) }` lives in one.
///
/// That is right, and it made the loop **not converge**. After a reader performs the extraction the
/// linter asked for, the call site it leaves behind is:
///
///     let matches = files.filter { search.matches(name: $0.name) }
///
/// …which the rule reports *again*, telling the reader to "extract it into a named value type" about
/// a closure whose entire body is a call to the value type they created one step earlier. All three
/// cold readers hit this; one walked the loop three times before stopping. **A rule that cannot
/// recognise its own advice being taken never terminates.**
///
/// The two closures are **syntactically identical** — one call, plain operands — so no amount of
/// local analysis separates them. What differs is semantic and non-local: `matches(name:)` is *ours*.
/// It is declared in this project, it is already seeded, and laws are already being proposed for it,
/// so the boundary has been drawn and there is nothing left to extract. `localizedCaseInsensitiveContains`
/// is Foundation's: it cannot be seeded, so the law has to be stated at the closure or nowhere.
///
/// Hence this collector. It answers exactly one question — *did we write this function?* — and the
/// closure rule needs no more than that.
///
/// ## What it records
///
/// Both the **base name** (`matches`) and the **labelled form** (`matches(name:)`). The labelled form
/// is what the closure rule matches on, because it is far harder to collide with by accident: a
/// project would have to declare a function with the same name *and* the same argument labels as the
/// stdlib call being shadowed. The bare name is kept for callers that cannot reconstruct labels.
///
/// Initializers, deinitializers and subscripts are not collected: none of them is a function a
/// closure can forward to in the shape this rule cares about.
public final class DeclaredFunctionCollector: SyntaxVisitor, TypeCollectorProtocol {

    public var collectedTypes: Set<String> { declared }

    private var declared: Set<String> = []

    public init() {
        super.init(viewMode: .sourceAccurate)
    }

    override public func visit(_ node: FunctionDeclSyntax) -> SyntaxVisitorContinueKind {
        let name = node.name.text
        declared.insert(name)
        declared.insert(Self.labelledName(name, node.signature.parameterClause.parameters))
        return .visitChildren
    }

    /// `matches` + `[name:]` → `matches(name:)`; an unlabelled parameter contributes `_:`.
    ///
    /// This mirrors how Swift itself names a function, so the string a caller reconstructs from a
    /// call site — `search.matches(name: x)` → `matches(name:)` — lines up with what was declared.
    public static func labelledName(
        _ baseName: String,
        _ parameters: FunctionParameterListSyntax
    ) -> String {
        let labels = parameters.map { parameter -> String in
            // `func f(_ x: Int)` has firstName `_`; `func f(name x: Int)` has firstName `name`.
            let label = parameter.firstName.text
            return "\(label):"
        }
        return "\(baseName)(\(labels.joined()))"
    }
}
