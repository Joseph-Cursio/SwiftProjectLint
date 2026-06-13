import SwiftProjectLintModels
import SwiftProjectLintRegistry
import SwiftProjectLintVisitors
import SwiftSyntax

/// Detects a State struct that declares **two or more** `@Presents` /
/// `@PresentationState` optional properties without collapsing them into a
/// single `destination` enum.
///
/// With independent presentation optionals, the "multiple modals presented at
/// once" combination is *representable* — nothing in the type prevents
/// `alert != nil && confirmationDialog != nil`. The idiomatic fix is a single
/// `@Presents var destination: Destination.State?` whose `Destination` is an
/// enum with one case per modal, which makes the illegal state
/// *unrepresentable* (a sum type holds one case at a time).
///
/// **Motivated by TCA example code.** PointFree's own Composable Architecture
/// case studies routinely model mutually-exclusive modals as separate optionals
/// (e.g. `AlertsAndConfirmationDialogs` with `@Presents var alert` +
/// `@Presents var confirmationDialog`, and `VoiceMemos` with `alert` +
/// `recordingMemo`). That code is *not buggy* — modality prevents both modals
/// at runtime — so this is an opt-in refactor suggestion (`.info`), not a bug.
final class MutuallyExclusivePresentationStateVisitor: BasePatternVisitor {

    required init(pattern: SyntaxPattern, viewMode: SyntaxTreeViewMode = .sourceAccurate) {
        super.init(pattern: pattern, viewMode: viewMode)
    }

    // MARK: - Visit

    override func visit(_ node: StructDeclSyntax) -> SyntaxVisitorContinueKind {
        let slots = presentationSlotCount(in: node)
        if slots >= 2 {
            addIssue(
                node: Syntax(node),
                variables: [
                    "typeName": node.name.text,
                    "count": String(slots)
                ]
            )
        }
        return .visitChildren
    }

    // MARK: - Detection

    /// Counts stored properties in `node` that are both annotated with a
    /// presentation wrapper (`@Presents` / `@PresentationState`) and of
    /// Optional type.
    private func presentationSlotCount(in node: StructDeclSyntax) -> Int {
        node.memberBlock.members.reduce(into: 0) { count, member in
            guard let varDecl = member.decl.as(VariableDeclSyntax.self),
                  hasPresentationAttribute(varDecl),
                  hasOptionalBinding(varDecl) else {
                return
            }
            count += 1
        }
    }

    /// Returns `true` when the property carries `@Presents` or
    /// `@PresentationState`.
    private func hasPresentationAttribute(_ varDecl: VariableDeclSyntax) -> Bool {
        varDecl.attributes.contains { element in
            guard case let .attribute(attribute) = element,
                  let identifier = attribute.attributeName.as(IdentifierTypeSyntax.self) else {
                return false
            }
            return identifier.name.text == "Presents"
                || identifier.name.text == "PresentationState"
        }
    }

    /// Returns `true` when any binding's declared type is Optional (`T?`).
    private func hasOptionalBinding(_ varDecl: VariableDeclSyntax) -> Bool {
        varDecl.bindings.contains { binding in
            binding.typeAnnotation?.type.is(OptionalTypeSyntax.self) ?? false
        }
    }
}
