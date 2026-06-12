import Foundation

/// Shared exemption logic for the protocol-architecture rules
/// (`SingleImplementationProtocol`, `MirrorProtocol`, …).
///
/// These rules independently ask the same sub-question: *is this protocol's
/// abstraction justified by something the rule should not penalise?* Two signals
/// matter:
///
/// 1. **A mock/test conformer exists.** The protocol is a dependency-injection
///    seam that lets tests substitute a fake. A protocol that mirrors a type 1:1
///    or has a single production conformer is the *expected* shape here, not a
///    smell — removing it would also remove the testing seam.
/// 2. **A dependency-injection *role* naming suffix** (`…Service`, `…Repository`,
///    …). A role word signals the author meant the type as a swappable dependency,
///    so it can justify the abstraction even before a second conformer exists. The
///    bare `…Protocol` suffix is deliberately *not* in this list: it is the universal
///    Swift naming convention for protocols, not a role signal, so treating it as
///    DI intent would exempt essentially every protocol and silence the rule.
///
/// Centralising these keeps the rules from contradicting each other about the same
/// protocol. Before this type existed, `MirrorProtocol` had no mock awareness, so it
/// flagged protocols like `CacheManagerProtocol` as "unnecessary abstraction" even
/// though `MockCacheManager` exists and `SingleImplementationProtocol` correctly
/// exempted it — and even while `ConcreteTypeUsage` was simultaneously asking callers
/// to depend on that very protocol.
///
/// Note the two signals are intentionally exposed separately rather than as one
/// "isJustified" flag: the mock-conformer signal is universal (a 1:1 mirror that is
/// genuinely mocked is justified), but the DI-suffix signal is rule-specific. The
/// `MirrorProtocol` rule deliberately does *not* exempt on suffix alone — every
/// mirror protocol ends in `Protocol`, so a blanket suffix exemption would silence
/// the rule entirely. Each rule composes the pieces it needs.
enum ProtocolExemption {

    /// Conformer-name fragments that mark a type as a test double.
    static let mockMarkers = ["Mock", "Fake", "Stub", "Spy"]

    /// Protocol-name *role* suffixes that imply dependency-injection intent.
    ///
    /// The bare `Protocol` suffix is intentionally absent: it is the conventional
    /// suffix on nearly every protocol (`FooProtocol`), so matching it would exempt
    /// essentially all protocols and prevent `SingleImplementationProtocol` from ever
    /// firing. Only role words — which describe a swappable dependency — qualify.
    static let diSuffixes = [
        "Providing", "Service", "Repository",
        "DataSource", "Client", "Networking"
    ]

    /// Path fragments that mark a file as test / fixture support.
    static let testPathFragments = ["Tests", "Mocks", "Fakes", "Stubs"]

    /// True when a conformer is a test double — either by name (`MockFoo`, `FooSpy`)
    /// or by living in a test/fixtures file. A `nil` `filePath` means "file unknown",
    /// in which case only the name signal applies.
    static func isTestConformer(name: String, filePath: String?) -> Bool {
        let isMockName = mockMarkers.contains { name.contains($0) }
        let isInTestFile = filePath.map { path in
            testPathFragments.contains { path.contains($0) } || path.hasSuffix("Test.swift")
        } ?? false
        return isMockName || isInTestFile
    }

    /// Splits `conformers` into production vs test/mock sets, resolving each
    /// conformer's originating file through `conformerFiles` (type name → path).
    static func partitionConformers(
        _ conformers: Set<String>,
        conformerFiles: [String: String]
    ) -> (production: Set<String>, test: Set<String>) {
        var production: Set<String> = []
        var test: Set<String> = []
        for conformer in conformers {
            if isTestConformer(name: conformer, filePath: conformerFiles[conformer]) {
                test.insert(conformer)
            } else {
                production.insert(conformer)
            }
        }
        return (production, test)
    }

    /// True when at least one conformer is a mock/test double — i.e. the protocol
    /// is a dependency-injection seam whose abstraction is justified for testing.
    static func hasTestConformer(
        _ conformers: Set<String>,
        conformerFiles: [String: String]
    ) -> Bool {
        partitionConformers(conformers, conformerFiles: conformerFiles).test.isEmpty == false
    }

    /// True when the protocol name ends in a dependency-injection suffix.
    static func hasDIIntentSuffix(_ protocolName: String) -> Bool {
        diSuffixes.contains { protocolName.hasSuffix($0) }
    }
}
