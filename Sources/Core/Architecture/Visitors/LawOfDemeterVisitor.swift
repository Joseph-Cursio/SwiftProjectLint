import Foundation
import SwiftSyntax

/// A SwiftSyntax visitor that detects deep member access chains (a.b.c.d or deeper)
/// where `a` is a plain identifier (not self/super). Deep chains expose
/// knowledge of an object's internal structure and violate the Law of Demeter.
///
/// Chains of 2 dots (a.b.c) are considered idiomatic in Swift and not flagged.
class LawOfDemeterVisitor: BasePatternVisitor {
    private var currentFilePath: String = ""

    /// Minimum number of dots to trigger a warning. 3 means a.b.c.d is flagged.
    private static let minChainDepth = 3

    /// Roots that are singleton/static accessors — chains starting here are
    /// standard Foundation/system API usage, not object-graph navigation.
    private static let singletonAccessors: Set<String> = [
        "default", "shared", "current", "main", "processInfo", "standard"
    ]

    /// Members that represent value transformations rather than object-graph
    /// navigation. When a chain passes through one of these members, subsequent
    /// access operates on a plain value rather than exposing internal structure.
    ///
    /// Examples:
    /// - `severity.rawValue.capitalized` — rawValue converts enum to primitive
    /// - `node.extendedType.description.trimmingCharacters` — description converts to String
    /// - `status.color.opacity` — color maps enum to a SwiftUI Color value
    /// - `range.lowerBound` / `range.upperBound` — standard Range value accessors
    /// - `memberAccess.declName.baseName.text` — SwiftSyntax token text accessor
    /// - `node.body.statements.isEmpty` — collection membership test
    private static let valueTransformMembers: Set<String> = [
        "rawValue", "hashValue", "capitalized", "uppercased", "lowercased",
        "description", "debugDescription", "trimmedDescription",
        "color", "lowerBound", "upperBound",
        // SwiftSyntax token accessors — reading identifier/token text is a value
        // transformation, not object-graph navigation into internal structure.
        "text", "baseName",
        // Boolean terminal — testing emptiness of a collection is a scalar result,
        // not further graph traversal (e.g., node.body.statements.isEmpty).
        "isEmpty",
    ]

    /// Well-known system chain prefixes that are idiomatic Foundation/system API usage.
    private static let exemptChainPrefixes: [[String]] = [
        ["FileManager", "default", "temporaryDirectory"],
        ["FileManager", "default", "homeDirectoryForCurrentUser"],
        ["FileManager", "default", "urls"],
        ["ProcessInfo", "processInfo", "arguments"],
        ["ProcessInfo", "processInfo", "environment"],
        ["Bundle", "main", "resourceURL"],
        ["Bundle", "main", "bundleURL"],
        ["Bundle", "main", "infoDictionary"],
        ["NotificationCenter", "default", "publisher"],
        ["URLSession", "shared", "data"],
        ["UserDefaults", "standard", "string"],
        ["UserDefaults", "standard", "bool"],
        ["DispatchQueue", "main", "async"],
    ]

    required init(pattern: SyntaxPattern, viewMode: SyntaxTreeViewMode = .sourceAccurate) {
        super.init(pattern: pattern, viewMode: viewMode)
    }

    override func setFilePath(_ filePath: String) {
        self.currentFilePath = filePath
    }

    override func visit(_ node: MemberAccessExprSyntax) -> SyntaxVisitorContinueKind {
        // Only report from the outermost MemberAccessExpr to avoid duplicates.
        // If our parent is also a MemberAccessExpr, we're not the outermost.
        if node.parent?.is(MemberAccessExprSyntax.self) == true {
            return .visitChildren
        }
        // Skip chains that are the callee of a function call — the called method
        // is part of the fluent interface, not additional graph traversal.
        // e.g., structNode.memberBlock.members.contains { ... }
        if node.parent?.is(FunctionCallExprSyntax.self) == true {
            return .visitChildren
        }

        // Walk down the chain to measure depth and collect components
        var components: [String] = [node.declName.baseName.text]
        var current: ExprSyntax? = node.base
        while let member = current?.as(MemberAccessExprSyntax.self) {
            components.append(member.declName.baseName.text)
            current = member.base
        }

        // current is now the root expression
        guard let root = current else { return .visitChildren }

        // Skip self.a.b.c — very common in ViewModels/Views
        if let rootRef = root.as(DeclReferenceExprSyntax.self),
           rootRef.baseName.text == "self" {
            return .visitChildren
        }
        // Skip super.a.b.c
        if root.is(SuperExprSyntax.self) { return .visitChildren }
        // Skip function-call chains (SwiftUI modifier chains, fluent APIs)
        if root.is(FunctionCallExprSyntax.self) { return .visitChildren }
        // Skip closure parameter chains ($0.severity.rawValue.capitalized)
        if root.trimmedDescription.hasPrefix("$") { return .visitChildren }

        // components has the member names in reverse order; add the root
        if let rootRef = root.as(DeclReferenceExprSyntax.self) {
            components.append(rootRef.baseName.text)
        } else {
            components.append(root.trimmedDescription)
        }

        // Total dots = components.count - 1 (e.g., a.b.c.d has 3 dots, 4 components)
        let dotCount = components.count - 1
        guard dotCount >= Self.minChainDepth else { return .visitChildren }

        // Build the chain in reading order for exemption checks
        let orderedComponents = Array(components.reversed())

        // Skip chains rooted at a capitalized name (type access / static / enum),
        // where the second component is a known singleton accessor
        if let rootName = orderedComponents.first,
           rootName.first?.isUppercase == true,
           orderedComponents.count > 1,
           Self.singletonAccessors.contains(orderedComponents[1]) {
            return .visitChildren
        }

        // Skip chains whose root is capitalized and that look like
        // nested-type or enum-case access (Type.Subtype.case.property)
        if let rootName = orderedComponents.first,
           rootName.first?.isUppercase == true,
           orderedComponents.count > 2,
           orderedComponents[1].first?.isUppercase == true {
            return .visitChildren
        }

        // Skip chains where a value-transform member appears before the violation
        // threshold. Once the chain converts to a plain value (e.g. .description,
        // .trimmedDescription, .color), the rest is value manipulation, not
        // object-graph navigation.
        // e.g., node.extendedType.description.trimmingCharacters — vtIndex("description") = 2 < 3
        // e.g., status.color.opacity — vtIndex("color") = 2 < 3
        if let vtIndex = orderedComponents.firstIndex(where: { Self.valueTransformMembers.contains($0) }),
           vtIndex < Self.minChainDepth {
            return .visitChildren
        }

        // Also skip chains of exactly minChainDepth whose terminal is a value-transform.
        // e.g., violation.severity.rawValue.capitalized — terminal "capitalized" in set, depth = 3
        // e.g., node.body.statements.isEmpty — terminal "isEmpty", depth = 3
        if let terminal = orderedComponents.last,
           Self.valueTransformMembers.contains(terminal),
           dotCount == Self.minChainDepth {
            return .visitChildren
        }

        // Skip well-known system API chain prefixes
        for prefix in Self.exemptChainPrefixes where orderedComponents.count >= prefix.count {
            if Array(orderedComponents.prefix(prefix.count)) == prefix {
                return .visitChildren
            }
        }

        // Skip test files — XCUI and test setup chains are inherently deep
        if currentFilePath.contains("Tests") || currentFilePath.hasSuffix("Test.swift") {
            return .visitChildren
        }

        let chain = orderedComponents.joined(separator: ".")
        let rootDesc = orderedComponents.first ?? "unknown"
        addIssue(
            severity: .info,
            message: "Chain '\(chain)' has \(dotCount) levels of nesting — " +
                "code knows too much about '\(rootDesc)'s internal structure",
            filePath: currentFilePath,
            lineNumber: getLineNumber(for: Syntax(node)),
            suggestion: "Ask only immediate collaborators; add a method to '\(rootDesc)' that encapsulates this access",
            ruleName: .lawOfDemeter
        )
        return .visitChildren
    }
}
