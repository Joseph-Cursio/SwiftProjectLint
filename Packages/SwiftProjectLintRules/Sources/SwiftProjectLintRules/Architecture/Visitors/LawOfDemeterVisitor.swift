import Foundation
import SwiftProjectLintModels
import SwiftProjectLintVisitors
import SwiftSyntax

/// A SwiftSyntax visitor that detects deep member access chains (a.b.c.d or deeper)
/// where `a` is a plain identifier (not self/super). Deep chains expose
/// knowledge of an object's internal structure and violate the Law of Demeter.
///
/// Chains of 2 dots (a.b.c) are considered idiomatic in Swift and not flagged.
class LawOfDemeterVisitor: BasePatternVisitor {
    private var currentFilePath: String = ""

    /// One finding per *reach-through*, not per occurrence.
    ///
    /// Keyed by the enclosing declaration and the penultimate component — the thing being reached
    /// into. Measured on two repositories before this existed: five sort comparators in
    /// SwiftInferProperties produced **48 findings for one missing `Comparable` conformance**, and
    /// eleven DTO-flattening constructors in SwiftAssist produced eleven for zero problems. The
    /// number never described anything a reader would act on that many times, and the largest
    /// cluster was the *easiest* fix — so counting occurrences inverted the priority.
    ///
    /// The key is the penultimate component rather than the root because that is what the
    /// encapsulation goes on: `lhs.member.location.file` and `rhs.member.location.line` are the same
    /// problem with `location`, and reporting them under `lhs` and `rhs` would split one fix in two.
    private var reportedReachThroughs: Set<ReachThrough> = []

    private struct ReachThrough: Hashable {
        /// Byte offset of the enclosing declaration, or 0 at file scope.
        let declarationPosition: Int
        /// The component being reached into — the penultimate hop.
        let target: String
    }

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
        super.setFilePath(filePath)
        self.currentFilePath = filePath
    }

    override func reset() {
        super.reset()
        reportedReachThroughs = []
    }

    /// The declaration a node sits in, identified by position. Chains in different functions are
    /// different problems even when they name the same target; chains in one function are one.
    private func enclosingDeclarationPosition(of node: Syntax) -> Int {
        var current: Syntax? = node.parent
        while let syntax = current {
            if Self.isDeclarationBoundary(syntax) {
                return syntax.positionAfterSkippingLeadingTrivia.utf8Offset
            }
            current = syntax.parent
        }
        return 0
    }

    /// The declarations a reach-through is scoped to. Split out from the walk above so the walk
    /// stays under the cyclomatic-complexity limit these five `is` checks pushed it over.
    private static func isDeclarationBoundary(_ syntax: Syntax) -> Bool {
        syntax.is(FunctionDeclSyntax.self) || syntax.is(InitializerDeclSyntax.self)
            || syntax.is(AccessorDeclSyntax.self) || syntax.is(VariableDeclSyntax.self)
            || syntax.is(SubscriptDeclSyntax.self)
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

        guard let (orderedComponents, dotCount) = qualifyingChain(from: node) else {
            return .visitChildren
        }
        guard dotCount >= Self.minChainDepth else { return .visitChildren }

        let chain = orderedComponents.joined(separator: ".")
        let rootDesc = orderedComponents.first ?? "unknown"
        let target = orderedComponents.count >= 2
            ? orderedComponents[orderedComponents.count - 2]
            : rootDesc

        // One finding per reach-through. A second chain into the same target from the same
        // declaration is the same problem and the same fix.
        let key = ReachThrough(
            declarationPosition: enclosingDeclarationPosition(of: Syntax(node)),
            target: target
        )
        guard reportedReachThroughs.insert(key).inserted else { return .visitChildren }

        addIssue(
            severity: .info,
            message: "Chain '\(chain)' has \(dotCount) levels of nesting — " +
                "code knows too much about '\(target)'s internal structure. Reported once per "
                + "declaration that reaches into '\(target)', however many times it does so",
            filePath: currentFilePath,
            lineNumber: getLineNumber(for: Syntax(node)),
            suggestion: "Ask only immediate collaborators; add a method or conformance to "
                + "'\(target)' that encapsulates this access",
            ruleName: .lawOfDemeter
        )
        return .visitChildren
    }

    /// The chain's components root-first and its depth, or `nil` when it is exempt or too shallow.
    ///
    /// Split out of `visit` so that walk stays under the cyclomatic-complexity limit once the
    /// reach-through key was added to it.
    private func qualifyingChain(
        from node: MemberAccessExprSyntax
    ) -> (components: [String], dotCount: Int)? {
        var components: [String] = [node.declName.baseName.text]
        var current: ExprSyntax? = node.base
        while let member = current?.as(MemberAccessExprSyntax.self) {
            components.append(member.declName.baseName.text)
            current = member.base
        }

        guard let root = current, isNonExemptRoot(root) else { return nil }

        if let rootRef = root.as(DeclReferenceExprSyntax.self) {
            components.append(rootRef.baseName.text)
        } else {
            components.append(root.trimmedDescription)
        }

        let dotCount = components.count - 1
        guard dotCount >= Self.minChainDepth else { return nil }

        let ordered = Array(components.reversed())
        guard isNonExemptChain(ordered, dotCount: dotCount) else { return nil }
        return (ordered, dotCount)
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

    /// Roots that put a chain outside the rule regardless of its depth.
    ///
    /// Split from `isNonExemptChain` to keep that within the cyclomatic-complexity budget.
    ///
    /// The underscore case is the substantive one: a leading underscore is Swift's
    /// convention for the implementation domain — a private stored property behind a
    /// computed one, or a library's own SPI. Demeter is about coupling to a *collaborator's*
    /// internals; reaching through your own storage is not that.
    private func hasExemptRoot(_ orderedComponents: [String]) -> Bool {
        guard let rootName = orderedComponents.first else { return false }
        if rootName.hasPrefix("_") { return true }
        return Self.environmentRoots.contains(rootName.lowercased())
    }

    private func isNonExemptChain(
        _ orderedComponents: [String], dotCount: Int
    ) -> Bool {
        if isTypePrefixedChain(orderedComponents) { return false }
        if hasExemptRoot(orderedComponents) { return false }
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
        if hasExemptMember(in: orderedComponents) { return false }
        // Skip test files
        if isTestOrFixtureFile() {
            return false
        }
        return true
    }

    /// True when the chain looks like a static-namespace traversal
    /// (`Foo.shared`, `Foo.Bar.something`) — both forms are syntactic
    /// type-prefix shapes that the Law-of-Demeter rule deliberately
    /// exempts. Folded into one helper so the main predicate stays
    /// within the cyclomatic-complexity budget.
    private func isTypePrefixedChain(_ orderedComponents: [String]) -> Bool {
        guard let rootName = orderedComponents.first,
              rootName.first?.isUppercase == true else { return false }
        if orderedComponents.count > 1,
           Self.singletonAccessors.contains(orderedComponents[1]) {
            return true
        }
        if orderedComponents.count > 2,
           orderedComponents[1].first?.isUppercase == true {
            return true
        }
        return false
    }

    /// True when the chain touches a framework/system API member
    /// (`SwiftSyntax` traversals, geometry/layout accessors) that the
    /// rule treats as legitimately long.
    private func hasExemptMember(in components: [String]) -> Bool {
        if components.contains(where: { Self.frameworkAPIMembers.contains($0) }) {
            return true
        }
        if components.contains(where: { Self.geometryMembers.contains($0) }) {
            return true
        }
        return false
    }
}
