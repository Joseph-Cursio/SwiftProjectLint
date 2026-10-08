import Foundation
import SwiftProjectLintModels
import SwiftProjectLintVisitors
import SwiftSyntax

/// Cross-file visitor: reports a requirement of a project protocol that no client calls *through
/// the protocol*. See `Docs/rules/unused-protocol-requirement.md`.
///
/// `Fat Protocol` counts requirements; interface segregation is about clients. A client is code
/// holding a value typed with the protocol (`any P`, `some P`, `T: P`, a stored property or
/// parameter typed `P`), and a requirement no client calls is one every client is made to depend
/// on without using. Calls on a concrete conformer do not count: they depend on the conformer,
/// not on the abstraction.
///
/// The client and call data is `ProtocolClientIndex`, built once from every file of the run in
/// `finalizeAnalysis`. This visitor only decides which protocols can be judged and which of their
/// requirements to report.
final class UnusedProtocolRequirementVisitor: CrossFileVisitorBase, CrossFilePatternVisitorProtocol {

    /// Requirements a framework calls by convention — a SwiftUI `body`, `Identifiable.id`,
    /// `hash(into:)` — which no call site in the project will show. A project protocol that
    /// restates one is never reported for it.
    static let frameworkRequirementNames: Set<String> = [
        // SwiftUI
        "body", "makeBody", "makeCoordinator", "sizeThatFits", "animatableData", "path",
        "makeUIView", "updateUIView", "dismantleUIView", "makeNSView", "updateNSView", "dismantleNSView",
        "makeUIViewController", "updateUIViewController", "makeNSViewController", "updateNSViewController",
        "defaultValue", "reduce", "transferRepresentation",
        // The standard library and Foundation
        "id", "hash", "hashValue", "encode", "description", "debugDescription",
        "errorDescription", "failureReason", "recoverySuggestion", "helpAnchor",
        "makeIterator", "next", "makeAsyncIterator", "rawValue", "allCases",
        "wrappedValue", "projectedValue", "unownedExecutor", "startIndex", "endIndex", "index",
        "objectWillChange"
    ]

    /// Framework protocols a project protocol may refine and still be judged: each one's
    /// requirements are static, initializers, or on `frameworkRequirementNames`, so a restated one
    /// is never reported. A protocol refining any other framework protocol is not judged — that
    /// framework calls requirements this rule cannot name (ArgumentParser's `validate()` on a
    /// `ParsableCommand`).
    static let knownFrameworkProtocols: Set<String> = [
        "Sendable", "AnyObject", "Actor", "AnyActor", "Copyable", "Escapable", "BitwiseCopyable",
        "SendableMetatype", "Equatable", "Hashable", "Comparable", "Identifiable", "Codable",
        "Encodable", "Decodable", "CustomStringConvertible", "CustomDebugStringConvertible", "Error",
        "LocalizedError", "CaseIterable", "RawRepresentable", "Sequence", "IteratorProtocol",
        "AsyncSequence", "AsyncIteratorProtocol", "View", "ViewModifier", "Shape", "App", "Scene",
        "Observable", "ObservableObject", "Transferable", "EnvironmentKey", "PreferenceKey"
    ]

    /// Attributes that change nothing about who calls a protocol's requirements. Any other
    /// attribute on a protocol is a macro, which may generate callers the run cannot see.
    static let inertAttributes: Set<String> = [
        "MainActor", "preconcurrency", "available", "usableFromInline", "_spi", "_marker", "Sendable"
    ]

    // The engine walks every file through the visitor; all the work is in `finalizeAnalysis`.
    override func visit(_ _: SourceFileSyntax) -> SyntaxVisitorContinueKind {
        .skipChildren
    }

    func finalizeAnalysis() {
        let sources = fileCache.sorted { $0.key < $1.key }.map { (path: $0.key, tree: $0.value) }
        let index = ProtocolClientIndex.build(from: sources)
        for name in index.protocols.keys.sorted() {
            for declaration in index.protocols[name] ?? [] where Self.canBeJudged(declaration, in: index) {
                report(declaration, in: index)
            }
        }
    }

    /// Whether every caller of the protocol's requirements can be in this run's sources.
    static func canBeJudged(_ declaration: ProtocolInfo, in index: ProtocolClientIndex) -> Bool {
        // `public`, `open` and `package` protocols have clients in modules the run cannot see —
        // the guard `UnusedProtocolAbstraction` has, for the same reason.
        guard declaration.modifiers.isDisjoint(with: ["public", "open", "package"]) else { return false }
        // Tests are clients, but a protocol declared in test or fixture code is scaffolding — the
        // reading `Could Be Private Member` takes of members declared there.
        guard isTestOrFixturePath(declaration.filePath) == false else { return false }
        // Objective-C protocols are delegates and data sources the frameworks call.
        guard declaration.attributeNames.contains("objc") == false,
              declaration.inheritedNames.contains("NSObjectProtocol") == false else {
            return false
        }
        guard declaration.attributeNames.allSatisfy({ inertAttributes.contains($0) || $0.hasSuffix("Actor") }) else {
            return false
        }
        return frameworkProtocolsRefined(by: declaration, in: index).isSubset(of: knownFrameworkProtocols)
    }

    /// Every name outside the run that the protocol refines, directly or through project protocols.
    static func frameworkProtocolsRefined(by declaration: ProtocolInfo, in index: ProtocolClientIndex) -> Set<String> {
        var framework: Set<String> = []
        var visited: Set<String> = [declaration.name]
        var pending = declaration.inheritedNames
        while let name = pending.popLast() {
            guard let refined = index.protocols[name] else {
                framework.insert(name)
                continue
            }
            if visited.insert(name).inserted {
                pending.append(contentsOf: refined.flatMap(\.inheritedNames))
            }
        }
        return framework
    }

    /// Instance methods, properties and subscripts. Static requirements and initializers are
    /// reached through metatypes (`T.make()`, `type(of: x).init()`), which this index does not
    /// follow; associated types are not called at all.
    static func isReportable(_ requirement: ProtocolRequirement) -> Bool {
        switch requirement.kind {
        case .method, .property, .subscriptMember:
            return requirement.isStatic == false && frameworkRequirementNames.contains(requirement.name) == false

        case .initializer, .associatedType:
            return false
        }
    }

    private func report(_ declaration: ProtocolInfo, in index: ProtocolClientIndex) {
        let clients = index.liveClients(of: declaration.name)
        // No clients at all is `Unused Protocol Abstraction`'s finding, not this one's.
        guard clients.isEmpty == false else { return }
        // A value that went somewhere untracked may reach any requirement.
        guard index.opaqueSites[declaration.name] == nil,
              clients.contains(where: \.escapes) == false else {
            return
        }
        let uses = clients.reduce(into: Set<MemberUse>()) { $0.formUnion($1.uses) }
        let isUsed: (ProtocolRequirement) -> Bool = { requirement in uses.contains { $0.matches(requirement) } }
        let counted = declaration.requirements.filter { $0.kind != .associatedType }
        let usedCount = counted.filter(isUsed).count
        let unused = declaration.requirements.filter { Self.isReportable($0) && isUsed($0) == false }
        for requirement in unused {
            addIssue(
                severity: .info,
                message: "Requirement '\(requirement.displayName)' of protocol '\(declaration.name)' is never "
                    + "called through the protocol — its clients use \(usedCount) of its "
                    + "\(counted.count) requirements.",
                filePath: declaration.filePath,
                lineNumber: requirement.line,
                suggestion: "Remove '\(requirement.displayName)' from '\(declaration.name)' and keep it on the "
                    + "conforming types that need it, or move it to a protocol for the clients that will call it.",
                ruleName: .unusedProtocolRequirement
            )
        }
    }
}
