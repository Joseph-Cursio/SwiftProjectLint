import SwiftSyntax

/// A cross-file SwiftSyntax visitor that detects `ObservableObject`-conforming classes
/// with `@Published` properties that are missing a `@MainActor` annotation.
///
/// **Why this matters:** In Swift 6 strict concurrency, mutations to `@Published` properties
/// must happen on the main actor — they drive view updates, which are inherently main-thread
/// operations. A class that omits `@MainActor` compiles cleanly but allows off-main-thread
/// mutation of UI state, leading to data races and undefined rendering behaviour.
///
/// **Detection:** Flags any `class` that:
/// 1. Conforms to `ObservableObject` in its inheritance clause.
/// 2. Has at least one `@Published` stored property.
/// 3. Is NOT itself annotated `@MainActor`.
///
/// **Cross-file suppression:** the two-pass walk/suppression machinery lives in
/// ``MainActorMissingVisitorBase``. Pass 1 collects the names of all explicitly
/// `@MainActor`-annotated classes; Pass 2 emits issues only for candidates whose
/// superclass is not in that set, suppressing false positives for subclasses that
/// inherit `@MainActor` isolation from a base class defined in another file.
///
/// **Known limitation:** Suppression covers one level of inheritance only (direct superclass).
/// Multi-level chains and base classes from external frameworks or SPM packages are not
/// in the file cache and cannot be suppressed automatically. Teams using
/// `swiftSettings: [.defaultIsolation(MainActor.self)]` in `Package.swift` will see
/// false positives; they should disable this rule for those targets.
final class MainActorMissingVisitor: MainActorMissingVisitorBase {

    override func isCandidate(_ node: ClassDeclSyntax) -> Bool {
        conformsToObservableObject(node) && hasPublishedProperties(node)
    }

    private func conformsToObservableObject(_ node: ClassDeclSyntax) -> Bool {
        guard let clause = node.inheritanceClause else { return false }
        return clause.inheritedTypes.contains {
            $0.type.as(IdentifierTypeSyntax.self)?.name.text == "ObservableObject"
        }
    }

    private func hasPublishedProperties(_ node: ClassDeclSyntax) -> Bool {
        node.memberBlock.members.contains { member in
            guard let varDecl = member.decl.as(VariableDeclSyntax.self) else { return false }
            return hasAttribute(varDecl.attributes, named: "Published")
        }
    }
}
