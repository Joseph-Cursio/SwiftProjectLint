@testable import Core
import SwiftParser
@testable import SwiftProjectLintRules
import SwiftSyntax
import Testing

/// False positives in the three `could-be-private` rules, each paired with a control.
///
/// Every case here asserts that something is **not** flagged, which a rule that had stopped
/// firing would satisfy just as well. So each is accompanied by a control differing only in
/// the element that makes the finding wrong — remove the protocol refinement, the member
/// exposing the type, the getter, the cross-file call — and the row must come back.
@Suite
struct CouldBePrivateFalsePositiveTests {

    private func walk(_ visitor: CrossFileVisitorBase, _ files: [String: SourceFileSyntax]) {
        for (name, ast) in files.sorted(by: { $0.key < $1.key }) {
            visitor.setFilePath(name)
            visitor.setSourceLocationConverter(SourceLocationConverter(fileName: name, tree: ast))
            visitor.walk(ast)
        }
    }

    private func typeIssues(_ sources: [String: String]) -> [LintIssue] {
        let files = sources.mapValues { Parser.parse(source: $0) }
        let visitor = CouldBePrivateVisitor(fileCache: files)
        visitor.setPattern(CouldBePrivate().pattern)
        walk(visitor, files)
        visitor.finalizeAnalysis()
        return visitor.detectedIssues.filter { $0.ruleName == .couldBePrivate }
    }

    private func memberIssues(_ sources: [String: String]) -> [LintIssue] {
        let files = sources.mapValues { Parser.parse(source: $0) }
        let visitor = CouldBePrivateMemberVisitor(fileCache: files)
        visitor.setPattern(CouldBePrivateMember().pattern)
        walk(visitor, files)
        visitor.finalizeAnalysis()
        return visitor.detectedIssues.filter { $0.ruleName == .couldBePrivateMember }
    }

    private func protocolIssues(_ sources: [String: String]) -> [LintIssue] {
        let files = sources.mapValues { Parser.parse(source: $0) }
        let visitor = ProtocolCouldBePrivateVisitor(fileCache: files)
        visitor.setPattern(ProtocolCouldBePrivate().pattern)
        walk(visitor, files)
        visitor.finalizeAnalysis()
        return visitor.detectedIssues.filter { $0.ruleName == .protocolCouldBePrivate }
    }

    // MARK: - A type reachable only through a member's type

    /// `RemovalEntry` is named nowhere but its own file, yet a caller reaching
    /// `cache.entries["k"]` holds one. Inference, not spelling, is what exposes it.
    @Test("a type exposed by a non-private member's annotation is not flagged")
    func typeOnAccessibleSurfaceIsNotFlagged() {
        let issues = typeIssues([
            "Cache.swift": """
            struct RemovalEntry {
                let reason: String
            }

            struct RemovalCache {
                var entries: [String: RemovalEntry] = [:]
            }
            """,
            "Consumer.swift": """
            struct CacheConsumer {
                func describe(_ cache: RemovalCache) -> String {
                    cache.entries.values.map(\\.reason).joined()
                }
            }
            """
        ])

        #expect(issues.contains { $0.message.contains("RemovalEntry") } == false)
    }

    /// Control: the same type, no longer named by any member. Nothing can receive one by
    /// inference, so the finding is correct and must still appear.
    @Test("control — a type no member exposes is still flagged")
    func typeOffAccessibleSurfaceIsStillFlagged() {
        let issues = typeIssues([
            "Cache.swift": """
            struct RemovalEntry {
                let reason: String
            }

            struct RemovalCache {
                var count: Int = 0
            }
            """,
            "Consumer.swift": """
            struct CacheConsumer {
                func describe(_ cache: RemovalCache) -> Int { cache.count }
            }
            """
        ])

        #expect(issues.contains { $0.message.contains("RemovalEntry") })
    }

    /// A `private` member is not part of the surface, so the type it names stays narrowable.
    @Test("a type exposed only by a private member is still flagged")
    func typeBehindPrivateMemberIsStillFlagged() {
        let issues = typeIssues([
            "Cache.swift": """
            struct RemovalEntry {
                let reason: String
            }

            struct RemovalCache {
                private var entries: [String: RemovalEntry] = [:]
                var count: Int { entries.count }
            }
            """,
            "Consumer.swift": """
            struct CacheConsumer {
                func describe(_ cache: RemovalCache) -> Int { cache.count }
            }
            """
        ])

        #expect(issues.contains { $0.message.contains("RemovalEntry") })
    }

    // MARK: - Locals inside an implicit getter

    /// `header` is a local binding in `var body: String { … }`, not a member at all.
    @Test("a local inside an implicit getter is not reported as a member")
    func localInImplicitGetterIsNotAMember() {
        let issues = memberIssues([
            "Report.swift": """
            struct Report {
                var body: String {
                    let header = "title"
                    return header + "!"
                }
            }
            """
        ])

        #expect(issues.contains { $0.message.contains("header") } == false)
    }

    /// Control: the same name as a genuine stored property is still flagged, so the case
    /// above is excluded for being a local rather than for the name being ignored.
    @Test("control — a stored property of the same name is still flagged")
    func storedPropertyIsStillFlagged() {
        let issues = memberIssues([
            "Report.swift": """
            struct Report {
                var header = "title"
                var body: String { header + "!" }
            }
            """
        ])

        #expect(issues.contains { $0.message.contains("header") })
    }

    /// An explicit `get { }` block was already handled by the `AccessorDeclSyntax` override;
    /// this pins that the new `.getter` counting did not start double-counting it.
    @Test("a local inside an explicit getter is not reported as a member")
    func localInExplicitGetterIsNotAMember() {
        let issues = memberIssues([
            "Report.swift": """
            struct Report {
                var body: String {
                    get {
                        let header = "title"
                        return header + "!"
                    }
                }
            }
            """
        ])

        #expect(issues.contains { $0.message.contains("header") } == false)
    }

    // MARK: - Backtick-escaped member names

    /// The declaration reads `` `default` `` and the call site reads `default`. Without
    /// normalising both, the two never match and the member looks unreferenced.
    @Test("a backticked member called from another file is not flagged")
    func backtickedMemberCalledElsewhereIsNotFlagged() {
        let issues = memberIssues([
            "Configuration.swift": """
            struct Configuration {
                func `default`() -> Int { 42 }
            }
            """,
            "User.swift": """
            struct ConfigurationUser {
                func value(_ config: Configuration) -> Int { config.default() }
            }
            """
        ])

        #expect(issues.contains { $0.message.contains("default") } == false)
    }

    /// Control: the same backticked member with no caller anywhere. Normalising the name
    /// must not make every backticked member unflaggable.
    @Test("control — a backticked member with no external caller is still flagged")
    func backtickedMemberWithNoCallerIsStillFlagged() {
        let issues = memberIssues([
            "Configuration.swift": """
            struct Configuration {
                func `default`() -> Int { 42 }
            }
            """,
            "Unrelated.swift": """
            struct Unrelated {
                func run() -> Int { 0 }
            }
            """
        ])

        #expect(issues.contains { $0.message.contains("default") })
    }

    // MARK: - A protocol reached through a refinement

    /// `BaseCapability`'s only reference is in its own file — the inheritance clause of
    /// `ExtendedCapability` beside it. A caller holding an `ExtendedCapability` elsewhere
    /// still calls `perform()`, so narrowing the parent would not compile.
    @Test("a protocol refined by an externally used protocol is not flagged")
    func refinedProtocolIsNotFlagged() {
        let issues = protocolIssues([
            "Protocols.swift": """
            protocol BaseCapability {
                func perform()
            }

            protocol ExtendedCapability: BaseCapability {
                func performTwice()
            }
            """,
            "User.swift": """
            struct CapabilityUser {
                let capability: any ExtendedCapability
                func run() { capability.perform() }
            }
            """
        ])

        #expect(issues.contains { $0.message.contains("BaseCapability") } == false)
    }

    /// Control: nothing outside the declaring file uses the child either, so both protocols
    /// really are file-local and both findings are correct.
    @Test("control — a refined protocol nobody uses externally is still flagged")
    func unusedRefinedProtocolIsStillFlagged() {
        let issues = protocolIssues([
            "Protocols.swift": """
            protocol BaseCapability {
                func perform()
            }

            protocol ExtendedCapability: BaseCapability {
                func performTwice()
            }
            """,
            "Unrelated.swift": """
            struct Unrelated {
                func run() -> Int { 0 }
            }
            """
        ])

        #expect(issues.contains { $0.message.contains("BaseCapability") })
    }

    /// Reachability is transitive: a grandchild used externally keeps the grandparent
    /// exposed just as a direct child would.
    @Test("reachability through a refinement is transitive")
    func transitiveRefinementIsNotFlagged() {
        let issues = protocolIssues([
            "Protocols.swift": """
            protocol BaseCapability {
                func perform()
            }

            protocol MiddleCapability: BaseCapability {
                func performTwice()
            }

            protocol TopCapability: MiddleCapability {
                func performThrice()
            }
            """,
            "User.swift": """
            struct CapabilityUser {
                let capability: any TopCapability
                func run() { capability.perform() }
            }
            """
        ])

        #expect(issues.contains { $0.message.contains("BaseCapability") } == false)
        #expect(issues.contains { $0.message.contains("MiddleCapability") } == false)
    }
}
