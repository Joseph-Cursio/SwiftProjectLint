@testable import Core
import SwiftParser
@testable import SwiftProjectLintRules
import SwiftSyntax
import Testing

/// The Law of Demeter measured by width: how much of one object's shape a file has learned.
///
/// Every case that asserts absence is paired with one that differs only in the thing under test,
/// since a rule that had stopped firing altogether would satisfy the absence just as well.
@Suite
struct WideReachThroughVisitorTests {

    private func analyze(_ files: [String: String]) -> [LintIssue] {
        let cache = files.mapValues { Parser.parse(source: $0) }
        let visitor = WideReachThroughVisitor(fileCache: cache)
        visitor.setPattern(WideReachThrough().pattern)
        for (name, ast) in cache.sorted(by: { $0.key < $1.key }) {
            visitor.setFilePath(name)
            visitor.setSourceLocationConverter(SourceLocationConverter(fileName: name, tree: ast))
            visitor.walk(ast)
        }
        visitor.finalizeAnalysis()
        return visitor.detectedIssues.filter { $0.ruleName == .wideReachThrough }
    }

    /// A file reaching into `identity` for the three members named.
    private func identityReader(_ suffix: String, third: String = "canonical") -> String {
        """
        struct User\(suffix) {
            func show(s: Suggestion) -> String {
                let a = s.identity.display
                let b = s.identity.normalized
                let c = s.identity.\(third)
                return a + b + c
            }
        }
        """
    }

    // MARK: - The trigger

    @Test("a file reading three members of one target reports")
    func threeMembersReport() throws {
        let source = """
        struct Emitter {
            func emit(inputs: Inputs) -> String {
                let kind = inputs.candidate.carrierKind
                let state = inputs.candidate.stateTypeName
                let name = inputs.candidate.qualifiedName
                return kind + state + name
            }
        }
        """
        let issue = try #require(analyze(["Emitter.swift": source]).first)
        #expect(issue.message.contains("'candidate'"))
        #expect(issue.message.contains("3 of its members"))
        // The members are named so the reader can see the shape that leaked.
        #expect(issue.message.contains("carrierKind"))
        #expect(issue.message.contains("qualifiedName"))
        #expect(issue.message.contains("stateTypeName"))
    }

    @Test("two members is below the threshold")
    func twoMembersDoNotReport() {
        let source = """
        struct Emitter {
            func emit(inputs: Inputs) -> String {
                let kind = inputs.candidate.carrierKind
                let state = inputs.candidate.stateTypeName
                return kind + state
            }
        }
        """
        #expect(analyze(["Emitter.swift": source]).isEmpty)
    }

    @Test("one member reached many times is a missing accessor, not a reported violation")
    func repeatedSingleMemberDoesNotReport() {
        let source = """
        struct Visitor {
            func a(site: Site) -> String { site.location.filePath }
            func b(site: Site) -> String { site.location.filePath }
            func c(site: Site) -> String { site.location.filePath }
            func d(site: Site) -> String { site.location.filePath }
        }
        """
        #expect(analyze(["Visitor.swift": source]).isEmpty)
    }

    // MARK: - Depth independence

    @Test("an ordinary two-dot chain is in scope, where depth-based rules see nothing")
    func twoDotChainsAreInScope() throws {
        // Every chain here is exactly two dots, so the Law of Demeter rule's three-dot
        // threshold cannot see any of them. Width is the whole signal.
        let source = """
        struct Wide {
            func run(inputs: Inputs) -> String {
                let a = inputs.candidate.one
                let b = inputs.candidate.two
                let c = inputs.candidate.three
                return a + b + c
            }
        }
        """
        let issue = try #require(analyze(["Wide.swift": source]).first)
        #expect(issue.message.contains("3 of its members"))
    }

    // MARK: - The idiom filter

    @Test("a member set repeated identically across three files is an idiom, not three faults")
    func recurringSignatureIsSuppressed() {
        let issues = analyze([
            "A.swift": identityReader("A"),
            "B.swift": identityReader("B"),
            "C.swift": identityReader("C")
        ])
        #expect(issues.isEmpty)
    }

    @Test("the same member set in only two files still reports")
    func signatureBelowIdiomThresholdReports() {
        let issues = analyze([
            "A.swift": identityReader("A"),
            "B.swift": identityReader("B")
        ])
        #expect(issues.count == 2)
    }

    @Test("a differing member set is not folded into an idiom")
    func differingSignaturesStillReport() {
        // Three files reach into `identity`, but one asks for a different third member, so
        // only the two that match each other could be idiomatic — and two is below the bar.
        let issues = analyze([
            "A.swift": identityReader("A"),
            "B.swift": identityReader("B"),
            "C.swift": identityReader("C", third: "slug")
        ])
        #expect(issues.count == 3)
    }

    // MARK: - Inherited exemptions

    @Test("chains rooted at self are not reach-throughs")
    func selfRootedChainsAreExempt() {
        let source = """
        struct Own {
            func run() -> String {
                let a = self.candidate.one
                let b = self.candidate.two
                let c = self.candidate.three
                return a + b + c
            }
        }
        """
        #expect(analyze(["Own.swift": source]).isEmpty)
    }

    @Test("SwiftSyntax traversals are framework API, not object-graph coupling")
    func frameworkChainsAreExempt() {
        let source = """
        struct Walk {
            func run(node: Node) -> String {
                let a = node.signature.parameterClause
                let b = node.signature.returnClause
                let c = node.signature.effectSpecifiers
                return a + b + c
            }
        }
        """
        #expect(analyze(["Walk.swift": source]).isEmpty)
    }

    @Test("test files are out of scope")
    func testFilesAreExempt() {
        let source = """
        struct MyFeatureTests {
            func run(inputs: Inputs) -> String {
                let a = inputs.candidate.one
                let b = inputs.candidate.two
                let c = inputs.candidate.three
                return a + b + c
            }
        }
        """
        #expect(analyze(["MyFeatureTests.swift": source]).isEmpty)
    }

    // MARK: - Reporting

    @Test("the finding is anchored in the file that does the reaching")
    func findingIsAnchoredAtTheReachingFile() throws {
        let source = """
        struct Emitter {
            func emit(inputs: Inputs) -> String {
                let a = inputs.candidate.one
                let b = inputs.candidate.two
                let c = inputs.candidate.three
                return a + b + c
            }
        }
        """
        let issue = try #require(analyze(["Emitter.swift": source]).first)
        #expect(issue.filePath == "Emitter.swift")
        #expect(issue.lineNumber == 3)
        #expect(issue.severity == .info)
    }
}
