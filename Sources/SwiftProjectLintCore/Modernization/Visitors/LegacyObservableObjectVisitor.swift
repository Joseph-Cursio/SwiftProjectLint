import SwiftSyntax

/// A SwiftSyntax visitor that detects legacy Combine-based observation patterns.
///
/// With the introduction of `@Observable` in iOS 17, the older `ObservableObject`/`@Published`
/// pattern and its associated property wrappers (`@StateObject`, `@ObservedObject`,
/// `@EnvironmentObject`) can be replaced with simpler alternatives.
final class LegacyObservableObjectVisitor: BasePatternVisitor {

    private static let legacyAttributes: [String: String] = [
        "StateObject": "Use @State with an @Observable class instead of @StateObject",
        "ObservedObject": "Use @Bindable or pass the object directly instead of @ObservedObject",
        "EnvironmentObject": "Use @Environment with an @Observable class instead of @EnvironmentObject",
        "Published": "Properties on @Observable classes are tracked automatically — remove @Published"
    ]

    required init(pattern: SyntaxPattern, viewMode: SyntaxTreeViewMode = .sourceAccurate) {
        super.init(pattern: pattern, viewMode: viewMode)
    }

    override func visit(_ node: VariableDeclSyntax) -> SyntaxVisitorContinueKind {
        guard pattern.name == .legacyObservableObject else { return .visitChildren }

        for attribute in node.attributes {
            guard let attr = attribute.as(AttributeSyntax.self),
                  let identifier = attr.attributeName.as(IdentifierTypeSyntax.self) else { continue }

            let name = identifier.name.text
            guard let suggestion = Self.legacyAttributes[name] else { continue }

            addIssue(
                severity: .info,
                message: "@\(name) is a legacy Combine-based observation pattern",
                filePath: getFilePath(for: Syntax(node)),
                lineNumber: getLineNumber(for: Syntax(node)),
                suggestion: suggestion,
                ruleName: .legacyObservableObject
            )
        }
        return .visitChildren
    }
}
