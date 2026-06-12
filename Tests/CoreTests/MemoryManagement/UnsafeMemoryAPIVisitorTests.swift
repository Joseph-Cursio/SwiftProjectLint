@testable import Core
import SwiftParser
@testable import SwiftProjectLintRules
import SwiftSyntax
import Testing

@Suite
struct UnsafeMemoryAPIVisitorTests {

    private func analyze(_ source: String) -> [LintIssue] {
        let pattern = SyntaxPattern(
            name: .unsafeMemoryAPI,
            visitor: UnsafeMemoryAPIVisitor.self,
            severity: .info,
            category: .memoryManagement,
            messageTemplate: "",
            suggestion: "",
            description: ""
        )
        let visitor = UnsafeMemoryAPIVisitor(pattern: pattern)
        visitor.walk(Parser.parse(source: source))
        return visitor.detectedIssues.filter { $0.ruleName == .unsafeMemoryAPI }
    }

    @Test func flagsUnsafeBitCast() throws {
        let issues = analyze("let raw = unsafeBitCast(value, to: Int.self)")
        #expect(issues.count == 1)
        let issue = try #require(issues.first)
        #expect(issue.severity == .info)
        #expect(issue.message.contains("unsafeBitCast"))
    }

    @Test func flagsPointerParameterType() {
        let issues = analyze("func f(_ ptr: UnsafeMutablePointer<Int>) { }")
        #expect(issues.contains { $0.message.contains("UnsafeMutablePointer") })
    }

    @Test func flagsAssumingMemoryBoundMethodCall() {
        let issues = analyze("let typed = raw.assumingMemoryBound(to: UInt8.self)")
        #expect(issues.contains { $0.message.contains("assumingMemoryBound") })
    }

    @Test func flagsWithUnsafeBytesMethodCall() {
        let issues = analyze("data.withUnsafeBytes { buffer in use(buffer) }")
        #expect(issues.contains { $0.message.contains("withUnsafeBytes") })
    }

    @Test func flagsUnmanagedFactory() {
        let issues = analyze("let ref = Unmanaged.passRetained(object)")
        #expect(issues.contains { $0.message.contains("Unmanaged") })
    }

    @Test func flagsUnmanagedTypeAnnotation() {
        let issues = analyze("var ref: Unmanaged<Foo>?")
        #expect(issues.contains { $0.message.contains("Unmanaged") })
    }

    @Test func flagsOpaquePointer() {
        let issues = analyze("var handle: OpaquePointer?")
        #expect(issues.contains { $0.message.contains("OpaquePointer") })
    }

    @Test func ignoresSafeCode() {
        let source = """
        struct Model {
            let values: [Int]
            func transform(_ input: String) -> Int { input.count }
        }
        """
        #expect(analyze(source).isEmpty)
    }

    @Test func ignoresSimilarlyNamedSafeSymbols() {
        // Not the unsafe APIs: a user-defined `bindMemory`-free type and a normal cast.
        let source = """
        let safe = value as? Int
        struct PointerLike { let address: Int }
        """
        #expect(analyze(source).isEmpty)
    }
}
