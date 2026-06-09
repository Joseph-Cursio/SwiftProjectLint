import SwiftSyntax

extension DeclModifierListSyntax {
    /// Whether the modifier list contains an explicit access-control keyword:
    /// `private`, `fileprivate`, `internal`, `public`, or `open`.
    ///
    /// Used by the "could be private" rules to skip declarations whose access
    /// is already stated — only declarations relying on the implicit `internal`
    /// default are candidates for narrowing.
    public var hasExplicitAccessControl: Bool {
        contains { modifier in
            let text = modifier.name.text
            return text == "private" || text == "fileprivate"
                || text == "public" || text == "open" || text == "internal"
        }
    }
}
