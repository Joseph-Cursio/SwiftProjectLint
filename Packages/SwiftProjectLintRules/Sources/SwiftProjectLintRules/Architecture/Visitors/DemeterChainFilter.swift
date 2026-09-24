import SwiftSyntax

/// Which member-access chains count as reaching into another object's internals.
///
/// Two rules ask this question and must answer it identically. ``LawOfDemeterVisitor`` reports a
/// single chain that is too deep; ``StructuralKnowledgeVisitor`` reports one declaration that
/// reaches into the same collaborator for many different members. They disagree about what is
/// worth reporting, not about what a reach-through *is* — so the depth threshold is a parameter
/// here and everything else is shared.
///
/// The exemption lists are the accumulated result of running the Law of Demeter rule over real
/// repositories; each entry below is there because it produced a false positive somewhere. Keeping
/// one copy is the point: two divergent copies would mean a chain exempt from one rule and flagged
/// by the other, for no reason a reader could discover.
///
/// The test-file check is deliberately *not* here. It needs the visitor's own file state, and both
/// callers apply it themselves.
enum DemeterChainFilter {

    /// Roots that are singleton/static accessors — chains starting here are
    /// standard Foundation/system API usage, not object-graph navigation.
    static let singletonAccessors: Set<String> = [
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
    /// - `range.start` / `range.end` — the same two bounds, as LSP and SourceKit spell them
    /// - `memberAccess.declName.baseName.text` — SwiftSyntax token text accessor
    /// - `node.body.statements.isEmpty` — collection membership test
    /// - `report.totals.regions.count` — a scalar count, on the same footing as `isEmpty`
    /// - `directory.absoluteURL.standardizedFileURL` — Foundation URL normalisation, URL to URL
    static let valueTransformMembers: Set<String> = [
        "rawValue", "hashValue", "capitalized", "uppercased", "lowercased",
        "description", "debugDescription", "trimmedDescription",
        "color", "lowerBound", "upperBound", "start", "end",
        // SwiftSyntax token/trivia accessors
        "text", "baseName", "tokenKind",
        // Scalar terminals — a number or a flag, not another object to traverse
        "isEmpty", "isNotEmpty", "count",
        // URL value normalisations — URL -> URL, and URL -> String
        "absoluteURL", "standardizedFileURL", "lastPathComponent",
        // Trivia terminals
        "containsComments", "isNotSingleSpaceWithoutComments",
        "withTrailingEmptyLineRemoved", "splitBlocks",
        // Other value terminals
        "length", "isEmptyOrNil"
    ]

    /// SwiftSyntax structural members that form idiomatic API access chains.
    /// Chains through these are framework API, not object-graph coupling.
    static let frameworkAPIMembers: Set<String> = [
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
    static let geometryMembers: Set<String> = [
        "frame", "size", "bounds", "origin", "width", "height",
        "minX", "minY", "maxX", "maxY", "midX", "midY",
        "contentSize", "safeAreaInsets"
    ]

    /// Root names that indicate environment/navigation context (case-insensitive).
    static let environmentRoots: Set<String> = [
        "environment", "theme", "settings", "configuration",
        "navigationPath", "navigator", "coordinator", "router"
    ]

    /// Well-known system chain prefixes that are idiomatic Foundation/system API usage.
    static let exemptChainPrefixes: [[String]] = [
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

    /// The chain's components root-first and its depth, or `nil` when it is exempt or too shallow.
    ///
    /// `minChainDepth` is both the reporting threshold and the width of two exemption windows
    /// below, which is why it is one parameter rather than two: a chain is judged against the
    /// depth its caller considers interesting.
    static func qualifyingChain(
        from node: MemberAccessExprSyntax,
        minChainDepth: Int
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
        guard dotCount >= minChainDepth else { return nil }

        let ordered = Array(components.reversed())
        guard isNonExemptChain(ordered, dotCount: dotCount, minChainDepth: minChainDepth) else {
            return nil
        }
        return (ordered, dotCount)
    }

    static func isNonExemptRoot(_ root: ExprSyntax) -> Bool {
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

    static func isInsideKeyPath(_ node: ExprSyntax) -> Bool {
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
    /// The underscore case is the substantive one: a leading underscore is Swift's
    /// convention for the implementation domain — a private stored property behind a
    /// computed one, or a library's own SPI. Demeter is about coupling to a *collaborator's*
    /// internals; reaching through your own storage is not that.
    static func hasExemptRoot(_ orderedComponents: [String]) -> Bool {
        guard let rootName = orderedComponents.first else { return false }
        if rootName.hasPrefix("_") { return true }
        return environmentRoots.contains(rootName.lowercased())
    }

    static func isNonExemptChain(
        _ orderedComponents: [String], dotCount: Int, minChainDepth: Int
    ) -> Bool {
        if isTypePrefixedChain(orderedComponents) { return false }
        if hasExemptRoot(orderedComponents) { return false }
        // Skip early value-transform
        if let vtIndex = orderedComponents.firstIndex(
            where: { valueTransformMembers.contains($0) }
        ), vtIndex < minChainDepth {
            return false
        }
        // Skip terminal value-transform at exact threshold
        if let terminal = orderedComponents.last,
           valueTransformMembers.contains(terminal),
           dotCount == minChainDepth {
            return false
        }
        // Skip well-known system API chain prefixes
        for prefix in exemptChainPrefixes
            where orderedComponents.count >= prefix.count {
            if Array(orderedComponents.prefix(prefix.count)) == prefix {
                return false
            }
        }
        if hasExemptMember(in: orderedComponents) { return false }
        return true
    }

    /// True when the chain looks like a static-namespace traversal
    /// (`Foo.shared`, `Foo.Bar.something`) — both forms are syntactic
    /// type-prefix shapes that these rules deliberately exempt.
    static func isTypePrefixedChain(_ orderedComponents: [String]) -> Bool {
        guard let rootName = orderedComponents.first,
              rootName.first?.isUppercase == true else { return false }
        if orderedComponents.count > 1,
           singletonAccessors.contains(orderedComponents[1]) {
            return true
        }
        if orderedComponents.count > 2,
           orderedComponents[1].first?.isUppercase == true {
            return true
        }
        return false
    }

    /// True when the chain touches a framework/system API member
    /// (`SwiftSyntax` traversals, geometry/layout accessors) that these
    /// rules treat as legitimately long.
    static func hasExemptMember(in components: [String]) -> Bool {
        if components.contains(where: { frameworkAPIMembers.contains($0) }) {
            return true
        }
        if components.contains(where: { geometryMembers.contains($0) }) {
            return true
        }
        return false
    }
}
