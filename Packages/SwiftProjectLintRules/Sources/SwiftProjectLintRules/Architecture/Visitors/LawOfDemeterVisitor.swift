import SwiftProjectLintModels
import SwiftProjectLintRegistry
import SwiftProjectLintVisitors
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
        // SwiftSyntax token/trivia accessors
        "text", "baseName", "tokenKind",
        // Boolean terminals — scalar results, not graph traversal
        "isEmpty", "isNotEmpty",
        // Trivia terminals
        "containsComments", "isNotSingleSpaceWithoutComments",
        "withTrailingEmptyLineRemoved", "splitBlocks",
        // Other value terminals
        "length", "isEmptyOrNil"
    ]

    /// SwiftSyntax structural members that form idiomatic API access chains.
    /// Chains through these are framework API, not object-graph coupling.
    private static let frameworkAPIMembers: Set<String> = [
        "signature", "parameterClause", "parameters",
        "genericArgumentClause", "arguments", "argumentNames",
        "inheritanceClause", "inheritedTypes",
        "memberBlock", "members", "modifiers",
        "leadingTrivia", "trailingTrivia",
        "returnClause", "body", "statements",
        "bindings", "accessorBlock", "accessors",
        "leftBrace", "rightBrace", "arrow",
        "funcKeyword", "atSign", "attributeName",
        "declName", "calledExpression",
        "indentationRanges", "expected", "actual",
        "importDecl", "inKeyword", "operator",
        "stringView", "lines", "onlyElement"
    ]

    /// Members related to geometry/layout that form natural access chains.
    private static let geometryMembers: Set<String> = [
        "frame", "size", "bounds", "origin", "width", "height",
        "minX", "minY", "maxX", "maxY", "midX", "midY",
        "contentSize", "safeAreaInsets"
    ]

    /// Root names that indicate environment/navigation context (case-insensitive).
    private static let environmentRoots: Set<String> = [
        "environment", "theme", "settings", "configuration",
        "navigationPath", "navigator", "coordinator", "router"
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
        ["DispatchQueue", "main", "async"]
    ]

    required init(pattern: SyntaxPattern, viewMode: SyntaxTreeViewMode = .sourceAccurate) {
        super.init(pattern: pattern, viewMode: viewMode)
    }

    override func setFilePath(_ filePath: String) {
        self.currentFilePath = filePath
    }

    override func visit(_ node: MemberAccessExprSyntax) -> SyntaxVisitorContinueKind {
        // Only report from the outermost MemberAccessExpr to avoid duplicates.
        if node.parent?.is(MemberAccessExprSyntax.self) == true {
            return .visitChildren
        }
        // Skip chains that are the callee of a function call
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

        guard let root = current else { return .visitChildren }
        guard isNonExemptRoot(root) else { return .visitChildren }

        if let rootRef = root.as(DeclReferenceExprSyntax.self) {
            components.append(rootRef.baseName.text)
        } else {
            components.append(root.trimmedDescription)
        }

        let dotCount = components.count - 1
        guard dotCount >= Self.minChainDepth else { return .visitChildren }

        let orderedComponents = Array(components.reversed())
        guard isNonExemptChain(orderedComponents, dotCount: dotCount) else {
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

    private func isNonExemptRoot(_ root: ExprSyntax) -> Bool {
        if let rootRef = root.as(DeclReferenceExprSyntax.self),
           rootRef.baseName.text == "self" { return false }
        if root.is(SuperExprSyntax.self) { return false }
        if root.is(FunctionCallExprSyntax.self) { return false }
        // Binding projections ($viewModel.user.name)
        if root.trimmedDescription.hasPrefix("$") { return false }
        // KeyPath literals (\.user.name) — inside a KeyPathExprSyntax parent
        if isInsideKeyPath(root) { return false }
        return true
    }

    private func isInsideKeyPath(_ node: ExprSyntax) -> Bool {
        var current: Syntax? = Syntax(node)
        while let parent = current?.parent {
            if parent.is(KeyPathExprSyntax.self) { return true }
            if parent.is(CodeBlockItemSyntax.self) { return false }
            current = parent
        }
        return false
    }

    private func isNonExemptChain(
        _ orderedComponents: [String], dotCount: Int
    ) -> Bool {
        // Skip type.singleton chains
        if let rootName = orderedComponents.first,
           rootName.first?.isUppercase == true,
           orderedComponents.count > 1,
           Self.singletonAccessors.contains(orderedComponents[1]) {
            return false
        }
        // Skip nested-type / enum-case chains
        if let rootName = orderedComponents.first,
           rootName.first?.isUppercase == true,
           orderedComponents.count > 2,
           orderedComponents[1].first?.isUppercase == true {
            return false
        }
        // Skip early value-transform
        if let vtIndex = orderedComponents.firstIndex(
            where: { Self.valueTransformMembers.contains($0) }
        ), vtIndex < Self.minChainDepth {
            return false
        }
        // Skip terminal value-transform at exact threshold
        if let terminal = orderedComponents.last,
           Self.valueTransformMembers.contains(terminal),
           dotCount == Self.minChainDepth {
            return false
        }
        // Skip well-known system API chain prefixes
        for prefix in Self.exemptChainPrefixes
            where orderedComponents.count >= prefix.count {
            if Array(orderedComponents.prefix(prefix.count)) == prefix {
                return false
            }
        }
        // Skip framework API chains (SwiftSyntax, etc.)
        if orderedComponents.contains(where: { Self.frameworkAPIMembers.contains($0) }) {
            return false
        }
        // Skip environment/navigation roots
        if let rootName = orderedComponents.first,
           Self.environmentRoots.contains(rootName.lowercased()) {
            return false
        }
        // Skip geometry/layout access chains
        if orderedComponents.contains(where: { Self.geometryMembers.contains($0) }) {
            return false
        }
        // Skip test files
        if currentFilePath.contains("Tests")
            || currentFilePath.hasSuffix("Test.swift") {
            return false
        }
        return true
    }
}
