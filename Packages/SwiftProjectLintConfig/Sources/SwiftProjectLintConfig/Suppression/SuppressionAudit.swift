import Foundation
import SwiftProjectLintModels

/// A suppression name that matched no rule, with the key the author probably meant.
public struct UnrecognizedSuppressionName: Sendable, Equatable {
    /// Path as the caller supplied it — this type does no path arithmetic of its own.
    public let filePath: String
    /// 1-based line of the directive comment.
    public let line: Int
    /// The token, exactly as written.
    public let name: String
    /// The rule key this most likely meant, when one can be identified.
    public let suggestion: String?
    /// Whether the directive is left naming no rules at all, and so suppresses nothing.
    public let directiveIsInert: Bool

    public init(filePath: String, line: Int, name: String, suggestion: String?, directiveIsInert: Bool) {
        self.filePath = filePath
        self.line = line
        self.name = name
        self.suggestion = suggestion
        self.directiveIsInert = directiveIsInert
    }
}

/// Finds suppression directives naming rules that do not exist.
///
/// Split from `InlineSuppressionFilter` on purpose. The filter returns early when a
/// file has no issues, so a diagnostic riding along with it would report a file's bad
/// directives only while that file happened to be failing something else — the
/// files where a suppression is *working* would be exactly the ones that stayed
/// quiet. This runs over source text alone and does not care what was found.
public enum SuppressionAudit {

    /// Every unrecognised rule name in `fileContent`.
    ///
    /// **Two linters disagree about this body and SwiftLint wins**, because it is
    /// the pre-commit gate. SwiftProjectLint's own `Map Used For Side Effects`
    /// reports the implicitly-returned `flatMap` here as a discarded result;
    /// SwiftLint's `implicit_return` rejects the explicit `return` that silences
    /// it. The SwiftProjectLint rule is wrong — it cannot see that a lone
    /// expression in a body *is* the return value — and the two findings this
    /// leaves are tracked rather than worked around.
    public static func unrecognizedNames(in fileContent: String, filePath: String) -> [UnrecognizedSuppressionName] {
        InlineSuppressionParser.parse(fileContent: fileContent).flatMap { directive in
            directive.unrecognizedNames.map { name in
                UnrecognizedSuppressionName(
                    filePath: filePath,
                    line: directive.line,
                    name: name,
                    suggestion: suggestion(for: name),
                    directiveIsInert: directive.rules.isEmpty
                )
            }
        }
    }

    /// The key `name` probably meant, or `nil`.
    ///
    /// Compares with hyphens removed, which is an exact match rather than a fuzzy
    /// one — and it is enough, because **the keys are derived from display names
    /// and the hyphens fall where the display name happens to put spaces**.
    /// `Legacy ObservableObject` gives `legacy-observableobject`, so the natural
    /// spelling `legacy-observable-object` is wrong in hyphens alone. 26 of the
    /// 208 rules have a key that is not the kebab-case of their own identifier,
    /// and both real-world mistakes found in the corpus were hyphen placement.
    ///
    /// Unambiguous by construction: no two rule keys collide once hyphens are
    /// dropped, which `suggestionsAreUnambiguous` pins so a future rule name
    /// cannot quietly make this a guess.
    public static func suggestion(for name: String) -> String? {
        let needle = normalized(name)
        guard needle.isEmpty == false else { return nil }
        return RuleIdentifier.allCases
            .first { normalized($0.suppressionKey) == needle }?
            .suppressionKey
    }

    static func normalized(_ key: String) -> String {
        key.lowercased().replacing("-", with: "")
    }

    /// One line per finding, for stderr.
    public static func notice(for names: [UnrecognizedSuppressionName]) -> String {
        let lines = names.map { entry -> String in
            let tail = entry.suggestion.map { " — did you mean '\($0)'?" }
                ?? " — no rule by that name."
            let effect = entry.directiveIsInert
                ? " This directive now suppresses nothing."
                : ""
            return "  \(entry.filePath):\(entry.line): unknown rule '\(entry.name)'\(tail)\(effect)"
        }
        return """
            Warning: \(names.count) suppression comment\(names.count == 1 ? "" : "s") \
            name a rule that does not exist.
            \(lines.joined(separator: "\n"))
            Rule keys are the lowercased display name with spaces replaced by hyphens, \
            which is the file name under Docs/rules/ — not always the spelling you would guess.
            """
    }
}
