import SwiftEffectInference
import SwiftProjectLintModels
import SwiftProjectLintVisitors
import Testing

extension SignatureAwareCollisionIntegrationTests {
    // MARK: - The round-2 MemoryPersistDriver shape

    @Test
    func protocolRequirementPlusExtensionDefaultPlusConcreteAnnotation_resolves() throws {
        // Faithful reproduction of round-2 `MemoryPersistDriver.create`:
        // - A protocol requirement declares `create(key:value:expires:)` (no body, unannotated).
        // - A protocol extension provides a default `create(key:value:)` (different arity, unannotated).
        // - The concrete conformer provides `create(key:value:expires:)` annotated non_idempotent.
        //
        // Pre-fix: bare-name policy withdraws all three → zero diagnostics on caller.
        // Post-fix: `create(key:value:expires:)` has exactly one ANNOTATED declaration
        //           (unannotated protocol requirement is ignored); entry survives;
        //           caller's call via the 3-arg form resolves and flags.
        let files: [String: String] = [
            "PersistDriver.swift": """
            protocol PersistDriver {
                func create(key: String, value: String, expires: String?) async throws
            }

            extension PersistDriver {
                func create(key: String, value: String) async throws {
                    try await create(key: key, value: value, expires: nil)
                }
            }
            """,
            "MemoryPersistDriver.swift": """
            struct MemoryPersistDriver: PersistDriver {
                /// @lint.effect non_idempotent
                func create(key: String, value: String, expires: String?) async throws {}
            }
            """,
            "Handler.swift": """
            /// @lint.context replayable
            func handleWebhook(driver: MemoryPersistDriver) async throws {
                try await driver.create(key: "id", value: "v", expires: nil)
            }
            """,
        ]

        let issues = runCrossFileContext(files: files).detectedIssues
        #expect(
            issues.count == 1,
            "Expected the post-fix policy to resolve the 3-arg create despite protocol/extension siblings"
        )
        let issue = try #require(issues.first)
        #expect(issue.message.contains("create"))
        #expect(issue.filePath == "Handler.swift")
    }

    // MARK: - Collision still fires when multiple ANNOTATED declarations disagree

    @Test
    func twoAnnotatedDeclarationsSameSignature_conflictingEffects_stillWithdraw() {
        // Signature-aware keying does NOT weaken real collisions: two annotated
        // declarations of the same signature with conflicting effects still
        // withdraw the entry.
        let files: [String: String] = [
            "Handler.swift": """
            /// @lint.effect idempotent
            func process() async throws {
                try await insert(1)
            }
            """,
            "DatabaseA.swift": """
            /// @lint.effect non_idempotent
            func insert(_ id: Int) async throws {}
            """,
            "DatabaseB.swift": """
            /// @lint.effect idempotent
            func insert(_ id: Int) async throws {}
            """,
        ]

        // Both `insert(_:)` declarations share signature; conflicting effects
        // withdraw; no diagnostic on caller.
        #expect(runCrossFileEffect(files: files).detectedIssues.isEmpty)
    }

    @Test
    func twoAnnotatedDeclarationsSameSignature_matchingEffects_keep() {
        let files: [String: String] = [
            "Handler.swift": """
            /// @lint.effect idempotent
            func process() async throws {
                try await insert(1)
            }
            """,
            "DatabaseA.swift": """
            /// @lint.effect non_idempotent
            func insert(_ id: Int) async throws {}
            """,
            "DatabaseB.swift": """
            /// @lint.effect non_idempotent
            func insert(_ id: Int) async throws {}
            """,
        ]

        let issues = runCrossFileEffect(files: files).detectedIssues
        #expect(issues.count == 1)
        #expect(issues.first?.message.contains("insert") == true)
    }

    // MARK: - Unannotated declarations are invisible

    @Test
    func symbolTable_onlyAnnotatedDeclarationsCountTowardCollision() {
        let table = tableOf(
            """
            func insert(_ id: Int) {}
            """,
            """
            /// @lint.effect non_idempotent
            func insert(_ id: Int) {}
            """,
            """
            func insert(_ id: Int) {}
            """
        )
        let signature = FunctionSignature(name: "insert", argumentLabels: ["_"])
        // Only one ANNOTATED declaration → not a collision, entry kept.
        #expect(table.isCollision(signature: signature) == false)
        #expect(table.effect(for: signature) == .nonIdempotent)
    }
}
