import Foundation
import SwiftProjectLintModels
import SwiftProjectLintVisitors
import SwiftSyntax

/// A value reconstructed field-by-field from one you already have — where a field you forget takes
/// its **default**, silently.
///
///     return Suggestion(
///         templateName: suggestion.templateName,
///         evidence: suggestion.evidence,
///         score: suggestion.score,
///         generator: metadata,
///         explainability: suggestion.explainability,
///         identity: suggestion.identity,
///         liftedOrigin: suggestion.liftedOrigin,
///         mockGenerator: suggestion.mockGenerator,
///         carrier: suggestion.carrier
///         // carrierTypeName:  ← forgotten. Defaults to nil. Compiles. Ships.
///     )
///
/// ## Why this is a bug and not a style
///
/// **The defaults are the whole mechanism.** If every parameter of the initialiser were required,
/// omitting one would be a *compile error* and this shape would be harmless. Because some parameters
/// have defaults, the omission produces a value that type-checks, renders correctly in every visible
/// respect, and is quietly missing part of itself. Nothing goes red. The bug is discovered later, by
/// someone wondering why a field they set is `nil` three stages downstream.
///
/// That is why the rule fires **only** when the constructed type's initialiser has defaulted
/// parameters — see `knownDefaultedInitializerTypes`. Without them there is nothing to lose.
///
/// ## The evidence
///
/// In SwiftInferProperties, `Suggestion` was rebuilt this way in **eight** places, and the same bug
/// was found and patched three separate times — each fix adding the missing argument and leaving the
/// trap armed for the next field:
///
/// - **V1.151** — `GeneratorSelection` dropped `carrierTypeName`; the index/verify path silently fell
///   back to the owner type.
/// - **Later** — `TemplateRegistry+CrossValidation` dropped `carrier`, `carrierTypeName`,
///   `liftedOrigin` *and* `mockGenerator`. Its own comment says so.
/// - **Then** — every one of those eight sites dropped a newly added `generatorRecipes`, which is the
///   half of a property law that decides whether the law can **fail at all**. The suggestion still
///   printed a confident score, having quietly stopped being able to find the bug.
///
/// A survey across five sibling repos found ~19 candidate sites. This is not one codebase's quirk.
///
/// ## The fix, and its honest caveat
///
/// Copy the value and mutate it — `var copy = x; copy.field = new` — which **cannot** drop a field,
/// and needs no edit when a field is added.
///
/// That requires the properties to be `var`. For a genuinely immutable struct the fix is different:
/// funnel every rebuild through **one** `with(…)` method on the type, so there is a single site to
/// update rather than eight. The suggestion says both, because telling a reader to mutate a `let` is
/// advice they cannot take.
///
/// `warning`; on by default. It is a silent-data-loss bug class, but the fix is sometimes a design
/// change (`let` → `var`), which should not be forced mid-hotfix.
final class LossyStructRebuildVisitor: BasePatternVisitor {

    private var fileIsTestOrFixture = false

    /// The smallest call worth looking at. Below this, "most of the arguments come from one value"
    /// is not a meaningful claim — `Point(x: p.x, y: 0)` is just arithmetic.
    private static let minimumArguments = 3

    required init(pattern: SyntaxPattern, viewMode: SyntaxTreeViewMode = .sourceAccurate) {
        super.init(pattern: pattern, viewMode: viewMode)
    }

    override func setFilePath(_ filePath: String) {
        super.setFilePath(filePath)
        fileIsTestOrFixture = isTestOrFixtureFile()
    }

    override func visit(_ node: FunctionCallExprSyntax) -> SyntaxVisitorContinueKind {
        guard !fileIsTestOrFixture,
              let typeName = constructedTypeName(of: node),
              // The gate that makes this a bug rather than a shape: with no defaulted parameters, a
              // forgotten field is a compile error and nothing can be lost.
              knownDefaultedInitializerTypes.contains(typeName),
              let rebuild = Rebuild(
                  call: node,
                  minimumArguments: Self.minimumArguments,
                  // `origin: origin` reads a PARAMETER when the enclosing function declares one by
                  // that name — not `self.origin`. Without this, every static factory that names its
                  // parameters after the type's fields reads as a self-copy. It fired nine times on
                  // one file of `LiftedSuggestion` factories, every one a false positive.
                  namesBoundLocally: locallyBoundNames(around: node),
                  // A `static` function has no `self` to copy from, so the bare-identifier form
                  // cannot mean what the rule thinks it means.
                  allowsImplicitSelf: !isInStaticContext(around: node)
              )
        else {
            return .visitChildren
        }

        // **Most of the arguments must come from one value.** This is the claim the rule is making,
        // and nothing substitutes for it. An earlier cut let a resolved type-match bypass the ratio,
        // and then fired on a constructor that read a single field off a same-typed value — which is
        // not a rebuild of anything.
        guard rebuild.isDominant else { return .visitChildren }

        let sourceType = resolvedType(of: rebuild.base, around: node)

        // Now: is it a copy, or a *projection*?
        //
        // When the source's type is known, it decides — and it decides both ways. Same type: a copy,
        // fire. **Different type: a projection, and a perfectly good thing to write.** Assembling a
        // `SemanticIndexEntry` out of a `Suggestion`'s fields looks identical from the arguments
        // alone, and firing on it would be crying wolf at ordinary code.
        //
        // When the type cannot be resolved locally, the ratio stands on its own — most of the
        // arguments coming from one value is strong enough evidence to report. That trades a little
        // precision for recall, deliberately: an unresolvable base should cost a false positive
        // rather than a missed bug.
        if let sourceType {
            guard sourceType == typeName else { return .visitChildren }
        } else {
            // A bare `label: label` names nothing, so an *unresolved* implicit self is not evidence
            // of anything. Only the explicit `other.member` form earns the ratio-alone path.
            guard !rebuild.isImplicitSelf else { return .visitChildren }
        }

        // The advice depends on something the rule may not know: whether `base` is the same type as
        // `T`. When it is, "copy and mutate" is the fix. When the type could not be resolved —
        // `base` is an untyped closure parameter, say — this may be a PROJECTION into a different
        // type, where copy-and-mutate is not merely unhelpful but impossible. Telling a reader to do
        // something they cannot do is worse than saying nothing, so the message says what it knows.
        let confirmed = sourceType == typeName

        addIssue(
            severity: .warning,
            message: confirmed
                ? "`\(typeName)` is rebuilt field-by-field from `\(rebuild.base)`. Its initialiser "
                    + "has defaulted parameters, so a field you forget takes its default SILENTLY — "
                    + "the value compiles, renders, and is quietly missing part of itself."
                : "Most of these arguments are copied out of `\(rebuild.base)`, and `\(typeName)`'s "
                    + "initialiser has defaulted parameters — so a field you forget to carry across "
                    + "takes its default SILENTLY rather than failing to compile.",
            filePath: getFilePath(for: Syntax(node)),
            lineNumber: getLineNumber(for: Syntax(node)),
            suggestion: confirmed
                ? "Copy and mutate: `var copy = \(rebuild.base); copy.field = new`. That cannot drop "
                    + "a field, and needs no edit when one is added. If the properties are `let`, "
                    + "funnel every rebuild through a single `with(…)` method on the type instead — "
                    + "one site to update rather than many."
                : "If `\(rebuild.base)` is a `\(typeName)`, copy and mutate it instead: `var copy = "
                    + "\(rebuild.base); copy.field = new`. If this is a projection into a different "
                    + "type, the copy-and-mutate fix does not apply — but the hazard does: add a "
                    + "test that a fully-populated source survives the projection, so a field added "
                    + "later cannot be quietly left behind.",
            ruleName: .lossyStructRebuild,
            symbol: typeName
        )
        return .visitChildren
    }

    /// The type an initializer call constructs — `Suggestion(…)` → `"Suggestion"`.
    ///
    /// A leading capital is the tell. A lowercase callee is a function, and a function returning a
    /// value assembled from another value's fields is a *projection*, which is a perfectly good thing
    /// to write.
    private func constructedTypeName(of call: FunctionCallExprSyntax) -> String? {
        guard let reference = call.calledExpression.as(DeclReferenceExprSyntax.self) else {
            return nil
        }
        let name = reference.baseName.text
        guard let first = name.first, first.isUppercase else { return nil }

        // `Self(…)` inside the type's own extension is the very shape the bug takes — resolve it, or
        // the rule is blind to every self-rebuild written the idiomatic way.
        if name == "Self" {
            return enclosingTypeName(around: call)
        }
        return name
    }

    /// The declared type of `name`, if this file says what it is.
    ///
    /// Looks at the enclosing function's parameters (`func rebuild(_ suggestion: Suggestion, …)`) and
    /// at local `let x: T = …` bindings. Deliberately local and deliberately incomplete: when it
    /// cannot answer, the ratio test decides, so an unresolvable base costs recall rather than
    /// precision.
    private func resolvedType(of name: String, around node: some SyntaxProtocol) -> String? {
        // A rebuild from `self` is a copy exactly when the enclosing type IS the type being built.
        // `Suggestion.withExplainability` rebuilding a `Suggestion` is the case; a `Suggestion`
        // method building a `SemanticIndexEntry` from its own fields is a projection and must not
        // fire.
        if name == "self" {
            return enclosingTypeName(around: node)
        }

        var cursor: Syntax? = node.parent
        while let current = cursor {
            if let function = current.as(FunctionDeclSyntax.self),
               let type = parameterType(of: name, in: function) {
                return type
            }
            // A local binding, in either of the two ways Swift lets you write one.
            if let block = current.as(CodeBlockSyntax.self),
               let type = localBindingType(of: name, in: block) {
                return type
            }
            cursor = current.parent
        }
        return nil
    }

    /// The declared type of `function`'s parameter named `name`, matched on the *internal*
    /// name — that is the one the body refers to.
    private func parameterType(of name: String, in function: FunctionDeclSyntax) -> String? {
        for parameter in function.signature.parameterClause.parameters {
            let internalName = parameter.secondName?.text ?? parameter.firstName.text
            if internalName == name {
                return parameter.type.trimmedDescription
            }
        }
        return nil
    }

    /// The declared type of a local binding named `name` declared directly inside `block`.
    private func localBindingType(of name: String, in block: CodeBlockSyntax) -> String? {
        for item in block.statements {
            guard let declaration = item.item.as(VariableDeclSyntax.self) else { continue }
            if let type = declaredType(of: name, in: declaration) { return type }
        }
        return nil
    }

    /// The type of a local binding named `name`, from an annotation **or from its initialiser**.
    ///
    ///     let visitor: FunctionScannerVisitor = …     // annotated
    ///     let visitor = FunctionScannerVisitor(…)     // inferred, but the type is right there
    ///
    /// Reading the initialiser matters: without it, a projection built from a locally-constructed
    /// value has an unresolvable base, falls through to the ratio, and reports. Real code —
    /// `let visitor = FunctionScannerVisitor(…)` followed by `ScannedCorpus(summaries:
    /// visitor.summaries, …)` — is a projection into a *different* type, and the type it needs to
    /// prove that is written on the line above.
    private func declaredType(of name: String, in declaration: VariableDeclSyntax) -> String? {
        for binding in declaration.bindings {
            guard binding.pattern.as(IdentifierPatternSyntax.self)?.identifier.text == name else {
                continue
            }
            if let annotation = binding.typeAnnotation {
                return annotation.type.trimmedDescription
            }
            // `let x = T(…)` — the constructor names the type.
            if let call = binding.initializer?.value.as(FunctionCallExprSyntax.self),
               let reference = call.calledExpression.as(DeclReferenceExprSyntax.self),
               let first = reference.baseName.text.first, first.isUppercase {
                return reference.baseName.text
            }
        }
        return nil
    }

    /// Every name the enclosing function binds — its parameters, and any `let`/`var` in its body.
    ///
    /// A bare `origin: origin` reads one of *these* when the name is among them. It is not a read of
    /// `self.origin`, and treating it as one turns every factory that names its parameters after the
    /// type's fields into a finding.
    private func locallyBoundNames(around node: some SyntaxProtocol) -> Set<String> {
        var cursor: Syntax? = node.parent
        while let current = cursor {
            if let function = current.as(FunctionDeclSyntax.self) {
                var names: Set<String> = []
                for parameter in function.signature.parameterClause.parameters {
                    let internalName = parameter.secondName?.text ?? parameter.firstName.text
                    if internalName != "_" { names.insert(internalName) }
                }
                if let body = function.body {
                    let collector = LocalNameCollector(viewMode: .sourceAccurate)
                    collector.walk(body)
                    names.formUnion(collector.names)
                }
                return names
            }
            cursor = current.parent
        }
        return []
    }

    /// A `static` function has no `self`, so a bare identifier there can never be a field read.
    private func isInStaticContext(around node: some SyntaxProtocol) -> Bool {
        var cursor: Syntax? = node.parent
        while let current = cursor {
            if let function = current.as(FunctionDeclSyntax.self) {
                return function.modifiers.contains { modifier in
                    modifier.name.tokenKind == .keyword(.static)
                        || modifier.name.tokenKind == .keyword(.class)
                }
            }
            cursor = current.parent
        }
        return false
    }

    /// The type whose body this call sits in — `struct Suggestion`, or `extension Suggestion`.
    private func enclosingTypeName(around node: some SyntaxProtocol) -> String? {
        var cursor: Syntax? = node.parent
        while let current = cursor {
            if let structDecl = current.as(StructDeclSyntax.self) { return structDecl.name.text }
            if let classDecl = current.as(ClassDeclSyntax.self) { return classDecl.name.text }
            if let enumDecl = current.as(EnumDeclSyntax.self) { return enumDecl.name.text }
            if let extensionDecl = current.as(ExtensionDeclSyntax.self) {
                return extensionDecl.extendedType.trimmedDescription
            }
            cursor = current.parent
        }
        return nil
    }
}

/// Every `let` / `var` / `if let` / `case let` bound in a function body.
private final class LocalNameCollector: SyntaxVisitor {

    var names: Set<String> = []

    override func visit(_ node: IdentifierPatternSyntax) -> SyntaxVisitorContinueKind {
        names.insert(node.identifier.text)
        return .visitChildren
    }
}

/// A call whose arguments are mostly reads from one value — either `other.member`, or a bare
/// `label: label` that is `self.label` with the `self.` left off.
private struct Rebuild {

    /// What a rebuild-from-`self` is recorded as. Not a real identifier, so it cannot collide with
    /// one; the message renders it as `self`.
    static let implicitSelf = "self"

    /// The value being copied from.
    let base: String

    /// Whether the source is `self`, read through bare identifiers rather than named.
    var isImplicitSelf: Bool { base == Self.implicitSelf }

    /// Whether *most* of the arguments come from it.
    ///
    /// The threshold is **`m > n/2`, capped at `n − 1`**: more than half the arguments are copied
    /// from one value, and — for a small call — at least all-but-one.
    ///
    /// **The majority bar rather than a supermajority, and the reason is the failure itself.** A
    /// realistic rebuild copies every field and *changes a few*; the more it changes, the likelier
    /// one gets forgotten. So the dangerous rebuild is the one with **several** computed arguments —
    /// and a 70% bar excludes precisely that. On the eleven-field `Suggestion` that motivated this
    /// rule, a rebuild altering four fields would have slipped under a 70% threshold and been missed,
    /// while being the exact shape in which the fifth field was dropped.
    ///
    /// The `n − 1` cap keeps small calls honest: `Point(x: p.x, y: p.y, z: 0)` is 2-of-3, which is a
    /// majority *and* all-but-one, and it is a copy.
    let isDominant: Bool

    init?(
        call: FunctionCallExprSyntax,
        minimumArguments: Int,
        namesBoundLocally: Set<String>,
        allowsImplicitSelf: Bool
    ) {
        let arguments = Array(call.arguments)
        guard arguments.count >= minimumArguments else { return nil }

        var counts: [String: Int] = [:]
        for argument in arguments {
            // `label: other.member` — an explicit source value.
            if let member = argument.expression.as(MemberAccessExprSyntax.self),
               let receiver = member.base?.as(DeclReferenceExprSyntax.self) {
                counts[receiver.baseName.text, default: 0] += 1
                continue
            }

            // `label: label` — a bare identifier whose name IS the argument label. Inside the type's
            // own body that is `self.label` with the `self.` left off, and it is the form the bug
            // most often takes: `Suggestion.withExplainability` and `VerifyEvidenceScoring` both
            // rebuilt `self` this way, and both dropped a field.
            //
            // But it is only a field read if the name is NOT bound locally. `origin: origin` in a
            // factory whose parameter is `origin` reads the parameter, and a `static` function has
            // no `self` at all — both are ordinary construction, not a copy.
            guard allowsImplicitSelf else { continue }
            if let reference = argument.expression.as(DeclReferenceExprSyntax.self),
               let label = argument.label?.text,
               reference.baseName.text == label,
               !namesBoundLocally.contains(label) {
                counts[Self.implicitSelf, default: 0] += 1
            }
        }

        guard let (base, matched) = counts.max(by: { $0.value < $1.value }), matched > 0 else {
            return nil
        }

        let total = arguments.count
        let majority = total / 2 + 1        // strictly more than half
        let threshold = min(majority, total - 1)

        self.base = base
        self.isDominant = matched >= threshold
    }
}
