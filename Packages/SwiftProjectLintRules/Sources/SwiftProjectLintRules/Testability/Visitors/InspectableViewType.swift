import SwiftSyntax

/// Reads a type annotation as `InspectableView<ViewType.X>`, through `?`, `!` and a module
/// qualifier. A closure, dictionary or array type that merely mentions one is not one.
struct InspectableViewType {
    /// What the `ViewType.X` argument of `InspectableView<…>` says: the receiver kind, the view
    /// type spelled as its accessor, and the subject type whose layout is walked.
    struct ViewTypeArgument {
        let kind: ReceiverKind
        let viewType: String?
        let subjectType: String?
    }

    let isInspectableView: Bool
    /// What a step on a value of this type does; see `ReceiverKind`.
    let kind: ReceiverKind
    /// `X` in `InspectableView<ViewType.X>`, spelled as its accessor: `ForEach` → `forEach`.
    let viewType: String?
    /// `T` in `InspectableView<ViewType.View<T>>`: the view whose layout is walked.
    let subjectType: String?
    /// A variadic parameter of this type: an array of such views, in the order they were passed.
    var isArgumentList = false
    /// Spelled `InspectableView<…>?` or `InspectableView<…>!`.
    let isOptional: Bool

    init(_ type: TypeSyntax) {
        isOptional = InspectionBindingResolver.isOptionalType(type)
        let current = Self.unwrapped(type)
        let generics: GenericArgumentClauseSyntax?
        if let identifier = current.as(IdentifierTypeSyntax.self), identifier.name.text == "InspectableView" {
            generics = identifier.genericArgumentClause
        } else if let member = current.as(MemberTypeSyntax.self), member.name.text == "InspectableView" {
            generics = member.genericArgumentClause
        } else {
            (isInspectableView, kind, viewType, subjectType) = (false, .typed, nil, nil)
            return
        }
        isInspectableView = true
        let argument = generics?.arguments.first?.argument.trimmedDescription ?? ""
        let argumentType = Self.read(viewTypeArgument: argument)
        kind = argumentType.kind
        viewType = argumentType.viewType
        subjectType = argumentType.subjectType
    }

    /// Through `?`, `!`, `Optional<…>`, `inout` and parentheses.
    static func unwrapped(_ type: TypeSyntax) -> TypeSyntax {
        var current = type
        while true {
            if let optional = current.as(OptionalTypeSyntax.self) {
                current = optional.wrappedType
            } else if let forced = current.as(ImplicitlyUnwrappedOptionalTypeSyntax.self) {
                current = forced.wrappedType
            } else if let attributed = current.as(AttributedTypeSyntax.self) {
                current = attributed.baseType
            } else if let tuple = current.as(TupleTypeSyntax.self), tuple.elements.count == 1,
                      let only = tuple.elements.first {
                current = only.type
            } else if let identifier = current.as(IdentifierTypeSyntax.self), identifier.name.text == "Optional",
                      let wrapped = identifier.genericArgumentClause?.arguments.first?.argument.as(TypeSyntax.self) {
                current = wrapped
            } else {
                return current
            }
        }
    }

    /// `ViewType.ClassifiedView` is a found view; `ViewType.View<T>` and `ViewType.ViewModifier<T>`
    /// have `T`'s body's views as children; `ViewType.X` is a SwiftUI view; anything else — a
    /// generic `V` — is unknown, and read as a SwiftUI view.
    static func read(viewTypeArgument text: String) -> ViewTypeArgument {
        let unqualified = text.hasPrefix("ViewInspector.") ? String(text.dropFirst("ViewInspector.".count)) : text
        guard unqualified.hasPrefix("ViewType.") else {
            return ViewTypeArgument(kind: .typed, viewType: nil, subjectType: nil)
        }
        let name = String(unqualified.dropFirst("ViewType.".count))
        if name == "ClassifiedView" || name == "ParentView" {
            return ViewTypeArgument(kind: .found, viewType: nil, subjectType: nil)
        }
        for wrapper in ["View<", "ViewModifier<"] where name.hasPrefix(wrapper) && name.hasSuffix(">") {
            let subject = name.dropFirst(wrapper.count).dropLast()
            return ViewTypeArgument(
                kind: .content, viewType: nil, subjectType: InspectionVocabulary.typeName(String(subject))
            )
        }
        return ViewTypeArgument(
            kind: .typed, viewType: InspectionVocabulary.accessorName(forViewType: name), subjectType: nil
        )
    }
}
