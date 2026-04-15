import SwiftProjectLintModels
import SwiftProjectLintRegistry
import SwiftProjectLintVisitors
import SwiftSyntax

/// A SwiftSyntax visitor that flags high-risk `@retroactive` conformances.
///
/// `@retroactive` marks a conformance where you make a type you don't own (from
/// module A) conform to a protocol you don't own (from module B). Swift 5.7+
/// warns about this because two libraries can independently declare the same
/// conformance, producing a linker conflict with undefined selection behavior.
///
/// **The flagged subset:** conformances where both the extended type and the
/// protocol are from the Swift standard library, Foundation, SwiftUI, UIKit,
/// AppKit, or Combine. These are the highest-risk cases because many libraries
/// may independently define the same conformance for the same framework types.
///
/// **Not flagged:** `@retroactive` where only one side is from a framework, or
/// where one side is the developer's own type — those have lower collision risk.
final class RetroactiveConformanceVisitor: BasePatternVisitor {

    /// Framework module names considered high-risk on both sides of a retroactive conformance.
    private static let highRiskModules: Set<String> = [
        "Swift",
        "Foundation",
        "SwiftUI",
        "UIKit",
        "AppKit",
        "Combine",
        "CoreData",
        "CoreFoundation",
        "CoreGraphics"
    ]

    required init(pattern: SyntaxPattern, viewMode: SyntaxTreeViewMode = .sourceAccurate) {
        super.init(pattern: pattern, viewMode: viewMode)
    }

    override func visit(_ node: ExtensionDeclSyntax) -> SyntaxVisitorContinueKind {
        guard let inheritanceClause = node.inheritanceClause else { return .visitChildren }

        let extendedTypeName = node.extendedType.trimmedDescription

        for inherited in inheritanceClause.inheritedTypes {
            guard let attributed = inherited.type.as(AttributedTypeSyntax.self) else { continue }

            let hasRetroactive = attributed.attributes.contains { element in
                guard let attr = element.as(AttributeSyntax.self) else { return false }
                return attr.attributeName.trimmedDescription == "retroactive"
            }
            guard hasRetroactive else { continue }

            let protocolName = attributed.baseType.trimmedDescription

            // Only flag when we can identify both sides as high-risk framework types
            guard isHighRiskFrameworkType(extendedTypeName),
                  isHighRiskFrameworkType(protocolName) else { continue }

            addIssue(
                severity: .warning,
                message: "@retroactive conformance of '\(extendedTypeName)' to '\(protocolName)' "
                    + "risks a linker conflict if another library defines the same conformance",
                filePath: getFilePath(for: Syntax(node)),
                lineNumber: getLineNumber(for: Syntax(node)),
                suggestion: "Wrap '\(extendedTypeName)' in your own type and conform the wrapper, "
                    + "or check that no dependency already provides this conformance.",
                ruleName: .retroactiveConformance
            )
        }

        return .visitChildren
    }

    /// Returns true when `typeName` is a simple identifier (no dots, no generics)
    /// that belongs to a high-risk framework module.
    ///
    /// Detection is name-based: the type must exactly match a known well-used
    /// framework type. Generic specializations like `Array<Foo>` are stripped
    /// to their base name (`Array`) before checking.
    private func isHighRiskFrameworkType(_ typeName: String) -> Bool {
        // Strip generic arguments: "Array<String>" -> "Array"
        let baseName = typeName.components(separatedBy: "<").first ?? typeName
        return Self.highRiskFrameworkTypes.contains(baseName.trimmingCharacters(in: .whitespaces))
    }

    /// Commonly used framework types that are high-risk targets for retroactive conformance.
    private static let highRiskFrameworkTypes: Set<String> = [
        // Swift stdlib
        "Array", "Set", "Dictionary", "String", "Int", "Double", "Float",
        "Bool", "Optional", "Result", "Sequence", "Collection",
        "RandomAccessCollection", "BidirectionalCollection",
        "MutableCollection", "RangeReplaceableCollection",
        "Hashable", "Equatable", "Comparable", "Codable",
        "Encodable", "Decodable", "Identifiable", "CustomStringConvertible",
        "Sendable", "Error",
        // Foundation
        "Date", "URL", "UUID", "Data", "NSObject", "NSString", "NSArray",
        "NSDictionary", "NSSet", "NSNumber", "NSDecimalNumber",
        "NSAttributedString", "NSMutableAttributedString",
        "DateComponents", "Calendar", "TimeZone", "Locale",
        "URLComponents", "URLRequest", "JSONDecoder", "JSONEncoder",
        // SwiftUI / UIKit / AppKit
        "View", "UIView", "NSView", "UIViewController", "NSViewController",
        "Color", "Font", "Image", "Shape",
        // Combine
        "Publisher", "Subject", "AnyCancellable"
    ]
}
