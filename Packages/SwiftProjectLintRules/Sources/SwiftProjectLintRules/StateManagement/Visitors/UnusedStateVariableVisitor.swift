import SwiftProjectLintModels
import SwiftProjectLintVisitors
import SwiftSyntax

/// Detects a `private` or `fileprivate` `@State` or `@StateObject` that nothing in its file names.
///
/// The check is a name count over the file's tokens. A property counts as used when its name
/// appears anywhere other than its own declaration: as `x`, as the projected `$x`, or as the
/// storage `_x` an initializer assigns. The access level is what makes a file-local count sound.
/// Nothing outside the file can reach a `private` or `fileprivate` member, extensions in other
/// files included, so a name the file never mentions is a name nothing mentions.
///
/// The count is deliberately generous. A local variable, a parameter or another type's member with
/// the same name also counts as a use. That can hide a real unused property, but it never reports
/// a used one. Wider access levels are skipped: an `internal` property could be read from another
/// file.
final class UnusedStateVariableVisitor: BasePatternVisitor {

    /// How often each name appears in the file, with `$x` and `_x` counted under `x`.
    private var nameCounts: [String: Int] = [:]

    required init(pattern: SyntaxPattern, viewMode: SyntaxTreeViewMode = .sourceAccurate) {
        super.init(pattern: pattern, viewMode: viewMode)
    }

    override func visit(_ node: SourceFileSyntax) -> SyntaxVisitorContinueKind {
        nameCounts = [:]
        for token in node.tokens(viewMode: .sourceAccurate) {
            switch token.tokenKind {
            case .identifier(let text), .dollarIdentifier(let text):
                for name in Self.namesCounted(by: text) {
                    nameCounts[name, default: 0] += 1
                }
            default:
                continue
            }
        }
        return .visitChildren
    }

    override func visit(_ node: VariableDeclSyntax) -> SyntaxVisitorContinueKind {
        guard isFileLocal(node), hasOwningWrapper(node) else { return .visitChildren }
        for binding in node.bindings {
            guard let identifier = binding.pattern.as(IdentifierPatternSyntax.self) else { continue }
            let name = Self.unescaped(identifier.identifier.text)
            // The declaration itself is the one occurrence an unused property has.
            if nameCounts[name, default: 0] <= 1 {
                addIssue(node: Syntax(identifier), variables: ["variableName": name])
            }
        }
        return .visitChildren
    }

    // MARK: - Helpers

    /// The names one token counts toward: `x` for `x`, `$x` and `_x`. A token spelled `_x` also
    /// counts toward itself, since a property may really be named `_x`.
    private static func namesCounted(by text: String) -> [String] {
        let name = unescaped(text)
        if name.hasPrefix("$") {
            return [String(name.dropFirst())]
        }
        if name.hasPrefix("_"), name.count > 1 {
            return [name, String(name.dropFirst())]
        }
        return [name]
    }

    private static func unescaped(_ text: String) -> String {
        text.filter { $0 != "`" }
    }

    /// `private` or `fileprivate` on the declaration itself. `private(set)` only narrows the
    /// setter, so the property can still be read from other files and does not count.
    private func isFileLocal(_ node: VariableDeclSyntax) -> Bool {
        node.modifiers.contains { modifier in
            modifier.detail == nil
                && (modifier.name.tokenKind == .keyword(.private) || modifier.name.tokenKind == .keyword(.fileprivate))
        }
    }

    private func hasOwningWrapper(_ node: VariableDeclSyntax) -> Bool {
        node.attributes.contains { element in
            guard let attribute = element.as(AttributeSyntax.self) else { return false }
            let name: String? = attribute.attributeName.as(IdentifierTypeSyntax.self)?.name.text
                ?? attribute.attributeName.as(MemberTypeSyntax.self)?.name.text
            return name == PropertyWrapper.state.rawValue || name == PropertyWrapper.stateObject.rawValue
        }
    }
}
