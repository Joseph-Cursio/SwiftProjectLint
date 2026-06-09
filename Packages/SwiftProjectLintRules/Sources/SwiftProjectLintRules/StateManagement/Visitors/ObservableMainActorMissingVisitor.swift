import SwiftSyntax

/// A cross-file SwiftSyntax visitor that detects `@Observable` classes that are not
/// annotated `@MainActor`.
///
/// **Why this matters:** The `@Observable` macro (Swift 5.9 / iOS 17+) synthesises
/// observation infrastructure for every stored property in the class. Those properties
/// drive SwiftUI view updates, which are inherently main-thread operations. Without
/// `@MainActor`, any code — including background `Task`s — can mutate observed state
/// off the main thread, producing data races and undefined rendering behaviour under
/// Swift 6 strict concurrency.
///
/// **Detection:** Flags any `class` declaration that:
/// 1. Has an `@Observable` attribute.
/// 2. Is NOT itself annotated `@MainActor`.
///
/// **Cross-file suppression:** the two-pass walk/suppression machinery lives in
/// ``MainActorMissingVisitorBase``. Pass 1 collects all explicitly `@MainActor`-annotated
/// class names; Pass 2 suppresses candidates whose direct superclass is in that set — the
/// subclass inherits main-actor isolation automatically.
///
/// **Known limitation:** Suppression covers one level of inheritance only. Multi-level
/// chains and classes from external frameworks or SPM packages are not in the file cache.
/// Teams using `swiftSettings: [.defaultIsolation(MainActor.self)]` in `Package.swift`
/// will see false positives; they should disable this rule for those targets.
final class ObservableMainActorMissingVisitor: MainActorMissingVisitorBase {

    override func isCandidate(_ node: ClassDeclSyntax) -> Bool {
        hasAttribute(node.attributes, named: "Observable")
    }
}
