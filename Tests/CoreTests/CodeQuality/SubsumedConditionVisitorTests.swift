@testable import Core
import SwiftParser
@testable import SwiftProjectLintRules
import SwiftSyntax
import Testing

@Suite
struct SubsumedConditionVisitorTests {

    /// `body` inside a function whose string parameters give `contains` its substring meaning.
    private static func inFunction(_ body: String) -> String {
        "func f(x: String, a: String, b: String, s: String, flag: Bool) {\n\(body)\n}"
    }

    private func issues(_ source: String) -> [LintIssue] {
        let tree = Parser.parse(source: source)
        let visitor = SubsumedConditionVisitor(pattern: SubsumedCondition().pattern)
        visitor.setFilePath("Test.swift")
        visitor.setSourceLocationConverter(SourceLocationConverter(fileName: "Test.swift", tree: tree))
        visitor.walk(tree)
        return visitor.detectedIssues.filter { $0.ruleName == .subsumedCondition }
    }

    // MARK: - The measured cases

    @Test("a contains whose literal contains the other's is subsumed in an ||")
    func yamlScalarClassifier() throws {
        let found = issues("""
            func isIntScalar(tagDescription: String) -> Bool {
                tagDescription.contains("int") || tagDescription.contains("tag:yaml.org,2002:int")
            }
            """)
        let issue = try #require(found.first)
        #expect(found.count == 1)
        let redundant = #"`tagDescription.contains("tag:yaml.org,2002:int")` can never change this `||`"#
        #expect(issue.message.contains(redundant))
        #expect(issue.message.contains("it implies `tagDescription.contains(\"int\")`"))
    }

    @Test("an empty string and a conflicting prefix both imply a negated prefix")
    func tableRowGate() {
        let found = issues("""
            func shouldParse(_ trimmed: String) -> Bool {
                if trimmed.isEmpty || trimmed.hasPrefix("+") || !trimmed.hasPrefix("|") { return false }
                return true
            }
            """)
        #expect(found.count == 2)
        #expect(found.contains { $0.message.hasPrefix("`trimmed.isEmpty`") })
        #expect(found.contains { $0.message.hasPrefix("`trimmed.hasPrefix(\"+\")`") })
    }

    // MARK: - The implication table

    @Test("an && reports the operand another implies", arguments: [
        #"x.hasPrefix("ab") && x.hasPrefix("a")"#,
        #"x == "abc" && x.contains("b")"#,
        #"x.hasSuffix(".swift") && !x.isEmpty"#,
        #"x.contains("ab") && x.contains("b")"#,
        #"!x.contains("a") && !x.contains("ab")"#
    ])
    func andChain(condition: String) {
        #expect(issues(Self.inFunction("let y = \(condition)")).count == 1, "\(condition)")
    }

    @Test("an || reports the operand that implies another", arguments: [
        #"x == "Package.swift" || x.hasSuffix(".swift")"#,
        #"x.hasPrefix("~/") || x.hasPrefix("~")"#,
        #"x == "a" || x == "a""#,
        #"x.hasSuffix(".xcodeproj") || x != "b""#
    ])
    func orChain(condition: String) {
        #expect(issues(Self.inFunction("let y = \(condition)")).count == 1, "\(condition)")
    }

    @Test("an if condition list is an &&")
    func conditionList() {
        #expect(issues(Self.inFunction(#"if x.hasPrefix("ab"), x.hasPrefix("a") { }"#)).count == 1)
    }

    @Test("a parenthesized operand is read through")
    func parenthesized() {
        #expect(issues(Self.inFunction(#"let y = (x.contains("ab")) || x.contains("b")"#)).count == 1)
    }

    // MARK: - Silent

    @Test("independent tests are not subsumed", arguments: [
        #"x == "Package.swift" || x == ".swiftpm""#,
        #"x.hasSuffix(".xcodeproj") || x.hasSuffix(".xcworkspace")"#,
        #"x.contains("Configuration") || x.isEmpty"#,
        #"x.hasPrefix("<td>") && x.contains("</td>")"#,
        #"x.hasPrefix("a") || !x.hasPrefix("ab")"#,
        #"!x.isEmpty && !x.contains("─")"#,
        #"x.hasPrefix("ab") || x.hasPrefix("a") && y"#
    ])
    func independent(condition: String) {
        #expect(issues(Self.inFunction("let y = \(condition)")).isEmpty, "\(condition)")
    }

    @Test("different receivers never imply each other")
    func differentReceivers() {
        #expect(issues(Self.inFunction(#"let y = a.contains("ab") || b.contains("a")"#)).isEmpty)
        #expect(issues(Self.inFunction(#"let y = s.lowercased().hasPrefix("ab") || s.hasPrefix("a")"#)).isEmpty)
    }

    @Test("interpolated or escaped literals are opaque")
    func opaqueLiterals() {
        #expect(issues(Self.inFunction(#"let y = x.contains("\(a)b") || x.contains("b")"#)).isEmpty)
        #expect(issues(Self.inFunction(#"let y = x.contains("a\n") || x.contains("a")"#)).isEmpty)
    }

    @Test("a chain mixing && and || is not read")
    func mixedChain() {
        #expect(issues(Self.inFunction(#"let y = x.contains("ab") || x.contains("a") && flag"#)).isEmpty)
    }

    // MARK: - contains on a collection is membership

    @Test("contains on a receiver not known to be a string is not read as a substring test")
    func collectionMembership() {
        #expect(issues("""
            func isPrivate(_ modifiers: [String]) -> Bool {
                modifiers.contains("fileprivate") || modifiers.contains("private")
            }
            """).isEmpty)
        #expect(issues("""
            func walk(_ components: [String]) -> Bool { components.contains("..") || components.contains(".") }
            """).isEmpty)
        // A collection's `contains` still implies it is not empty.
        #expect(issues("""
            func any(_ names: Set<String>) -> Bool { names.contains("a") && !names.isEmpty }
            """).count == 1)
    }

    @Test("string evidence: a parameter, a local, a cast, a producing call, or the chain itself", arguments: [
        #"func f(_ s: Substring) -> Bool { s.contains("ab") || s.contains("a") }"#,
        #"func f() -> Bool { let s: String = load(); return s.contains("ab") || s.contains("a") }"#,
        #"func f(_ v: Any) -> Bool { if let s = v as? String, s.contains("ab") || s.contains("a") { return true }; return false }"#,
        #"func f(_ v: String) -> Bool { let s = v.replacingOccurrences(of: " ", with: ""); return s.contains("ab") || s.contains("a") }"#,
        #"func f(_ line: String) -> Bool { line.trimmingCharacters(in: .whitespaces).contains("ab") || line.trimmingCharacters(in: .whitespaces).contains("a") }"#,
        #"func f(_ s: T) -> Bool { s.hasPrefix("x") || s.contains("ab") || s.contains("a") }"#
    ])
    func stringEvidence(source: String) {
        #expect(issues(source).count == 1, "\(source)")
    }
}
