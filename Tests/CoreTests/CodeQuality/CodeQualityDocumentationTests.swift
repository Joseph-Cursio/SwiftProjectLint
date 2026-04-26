import Testing
import Foundation
import SwiftParser
import SwiftSyntax
@testable import Core
@testable import SwiftProjectLintRules

struct CodeQualityDocumentationTests {

    // MARK: - Test Helper Methods

    private func createVisitor() -> DocumentationVisitor {
        let visitor = DocumentationVisitor(patternCategory: .codeQuality)
        visitor.setFilePath("TestFile.swift")
        return visitor
    }

    private func createStrictVisitor() -> DocumentationVisitor {
        let visitor = DocumentationVisitor(patternCategory: .codeQuality, configuration: .strict)
        visitor.setFilePath("TestFile.swift")
        return visitor
    }

    // MARK: - Missing Documentation Tests

    @Test func testMissingDocumentationDetection() throws {
        let visitor = createVisitor()

        // Given
        let sourceCode = """
        public struct TestView: View {
            public func publicFunction() {
                // No documentation
            }

            var body: some View {
                Text("Hello")
            }
        }

        public class TestClass {
            public func anotherPublicFunction() {
                // No documentation
            }
        }
        """

        // When
        let sourceFile = Parser.parse(source: sourceCode)
        visitor.walk(sourceFile)

        // Then
        #expect(visitor.detectedIssues.filter { $0.ruleName == .missingDocumentation }.count == 4)

        let documentationIssues = visitor.detectedIssues.filter { $0.message.contains("documentation") }
        #expect(documentationIssues.count == 4)

        let structIssue = try #require(documentationIssues.first { $0.message.contains("TestView") })
        _ = structIssue

        let functionIssue = try #require(documentationIssues.first { $0.message.contains("publicFunction") })
        _ = functionIssue

        let classIssue = try #require(documentationIssues.first { $0.message.contains("TestClass") })
        _ = classIssue

        let anotherFunctionIssue = try #require(
            documentationIssues.first { $0.message.contains("anotherPublicFunction") }
        )
        _ = anotherFunctionIssue
    }

    @Test func testDocumentedAPIsNoDetection() throws {
        let visitor = createVisitor()

        // Given
        let sourceCode = """
        /// A test view for demonstration purposes
        public struct TestView: View {
            /// A public function with documentation
            public func publicFunction() {
                // Has documentation
            }

            var body: some View {
                Text("Hello")
            }
        }
        """

        // When
        let sourceFile = Parser.parse(source: sourceCode)
        visitor.walk(sourceFile)

        // Then
        #expect(visitor.detectedIssues.filter { $0.ruleName == .missingDocumentation }.isEmpty)
    }

    @Test func testPrivateAPIsNoDetection() throws {
        let visitor = createVisitor()

        // Given
        let sourceCode = """
        struct TestView: View {
            func privateFunction() {
                // No documentation but private
            }

            var body: some View {
                Text("Hello")
            }
        }
        """

        // When
        let sourceFile = Parser.parse(source: sourceCode)
        visitor.walk(sourceFile)

        // Then
        #expect(visitor.detectedIssues.filter { $0.ruleName == .missingDocumentation }.isEmpty)
    }

    @Test func testDocumentationDetectionCharacterization() throws {
        let visitor = createVisitor()
        // Given
        let sourceCode = """
        public struct TestView: View {
            var body: some View { Text("Hello") }
        }
        """
        // When
        let sourceFile = Parser.parse(source: sourceCode)
        visitor.walk(sourceFile)
        // Then - public struct without doc comment should produce an issue
        #expect(visitor.detectedIssues.isEmpty == false)
    }

    @Test func testStrictDocumentationDetectionCharacterization() throws {
        let visitor = createStrictVisitor()
        // Given
        let sourceCode = """
        public struct TestView: View {
            var body: some View { Text("Hello") }
        }
        """
        // When
        let sourceFile = Parser.parse(source: sourceCode)
        visitor.walk(sourceFile)
        // Then - strict mode on public struct without doc comment should produce an issue
        #expect(visitor.detectedIssues.isEmpty == false)
    }

    // MARK: - Protocol-required stub exemptions (slice C)

    @Test func macroExpansionMethod_isExempt() throws {
        // Cross-adopter evidence: SwiftIdempotency package scan (2026-04-26)
        // showed 6 fires across 4 marker macro types — every macro-impl
        // file pays the documentation-warning toll on protocol-required
        // boilerplate. The expansion(...) method's documentation belongs
        // at the SwiftSyntax Macro protocol declaration site, not at every
        // adopter conformance.
        let visitor = createVisitor()
        let sourceCode = """
        public struct IdempotentMacro: PeerMacro {
            public static func expansion(
                of node: AttributeSyntax,
                providingPeersOf declaration: some DeclSyntaxProtocol,
                in context: some MacroExpansionContext
            ) throws -> [DeclSyntax] {
                []
            }
        }
        """
        let sourceFile = Parser.parse(source: sourceCode)
        visitor.walk(sourceFile)
        let methodIssues = visitor.detectedIssues.filter {
            $0.ruleName == .missingDocumentation && $0.message.contains("expansion")
        }
        #expect(methodIssues.isEmpty)
    }

    @Test func encodeToEncoderMethod_isExempt() throws {
        // Encodable-required `encode(to:)`. Documentation lives at the
        // protocol declaration site (Apple's Foundation), not at the
        // conforming type.
        let visitor = createVisitor()
        let sourceCode = """
        public struct IdempotencyKey: Encodable {
            public func encode(to encoder: Encoder) throws {}
        }
        """
        let sourceFile = Parser.parse(source: sourceCode)
        visitor.walk(sourceFile)
        let methodIssues = visitor.detectedIssues.filter {
            $0.ruleName == .missingDocumentation && $0.message.contains("encode")
        }
        #expect(methodIssues.isEmpty)
    }

    @Test func nonStaticExpansionMethod_stillFires() throws {
        // Receiver-gate: only `static func expansion(...)` is exempt —
        // adopter-defined non-static `expansion` methods still fire as
        // missing documentation. Protects the exemption from collisions
        // with adopter code that coincidentally uses the name `expansion`
        // for non-macro purposes.
        let visitor = createVisitor()
        let sourceCode = """
        public struct Engine {
            public func expansion() -> Int { 0 }
        }
        """
        let sourceFile = Parser.parse(source: sourceCode)
        visitor.walk(sourceFile)
        let methodIssues = visitor.detectedIssues.filter {
            $0.ruleName == .missingDocumentation && $0.message.contains("expansion")
        }
        #expect(!methodIssues.isEmpty,
                "non-static expansion(...) should still fire missingDocumentation")
    }

    @Test func encodeWithoutToLabel_stillFires() throws {
        // Receiver-gate: only `encode(to:)` (the Encodable shape) is
        // exempt. Methods named `encode` with different parameter labels
        // (e.g. `encode(_ value:)`) still fire.
        let visitor = createVisitor()
        let sourceCode = """
        public struct Codec {
            public func encode(_ value: String) -> Data { Data() }
        }
        """
        let sourceFile = Parser.parse(source: sourceCode)
        visitor.walk(sourceFile)
        let methodIssues = visitor.detectedIssues.filter {
            $0.ruleName == .missingDocumentation && $0.message.contains("encode")
        }
        #expect(!methodIssues.isEmpty,
                "encode(_:) should still fire missingDocumentation")
    }
}
