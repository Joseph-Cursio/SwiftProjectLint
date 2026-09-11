@testable import Core
import Foundation
import SwiftParser
@testable import SwiftProjectLintRules
import SwiftSyntax
import Testing

/// Parse `source`, run only this rule's visitor, and return what it reported.
///
/// File-scope and internal so `ArchitectureBooleanControlCouplingExemptionTests`
/// can use it too. The two suites are split across two files only to keep either
/// half under `type_body_length`; they are one set of tests.
///
/// **Named for its rule, not `analyzeSource`.** Most test files here declare a
/// `private func analyzeSource` of their own. An *internal* one with that name
/// wins overload resolution against a private sibling that defaults more
/// parameters, so it silently captures the other file's call sites — it compiles,
/// and the tests run against the wrong visitor. Fourteen `ConcreteTypeUsage`
/// tests failed that way while this helper was still called `analyzeSource`.
func analyzeBooleanControlCoupling(
    _ source: String,
    filePath: String = "Sample.swift"
) -> [LintIssue] {
    let visitor = BooleanControlCouplingVisitor(patternCategory: .architecture)
    let syntax = Parser.parse(source: source)
    let converter = SourceLocationConverter(fileName: filePath, tree: syntax)
    visitor.setSourceLocationConverter(converter)
    visitor.setFilePath(filePath)
    visitor.walk(syntax)
    return visitor.detectedIssues.filter { $0.ruleName == .booleanControlCoupling }
}

@Suite
struct ArchitectureBooleanControlCouplingViolationTests {

    // Several fixtures below carry two statements per arm where one call would
    // have read more naturally. That is deliberate: their subject is condition
    // and scope detection (negation, compound conditions, initializers, `else
    // if` chains), and a one-call arm now matches `isNamedDispatch`, so writing
    // them the short way would test the gate instead of the thing named in the
    // test.

    @Test func flagsTwoUnnamedPathsGatedOnBoolParameter() throws {
        // The rule doc's rationale example: each arm does work that has no name
        // yet, which is what a strategy would give it.
        let source = """
        struct Reports {
            func export(_ report: Report, asPDF: Bool) {
                if asPDF {
                    renderPDF(report)
                    attachMetadata(report)
                } else {
                    renderHTML(report)
                    inlineStyles(report)
                }
            }
        }
        """
        let issues = analyzeBooleanControlCoupling(source)
        let issue = try #require(issues.first)
        #expect(issue.message.contains("asPDF"))
    }

    @Test func flagsLopsidedArmsWhereOnlyOneSideIsOneStatement() {
        // `pbt-book`'s `tokenizeStreaming(_:buggy:)`, reduced: one line against
        // several. Asymmetry is the signature of two algorithms, and it is why
        // `isNamedDispatch` tests *both* arms instead of putting a floor under
        // each one — a floor would silence this and spare the dispatch pairs.
        let source = """
        struct Tokenizer {
            func tokenize(_ chunks: [String], buggy: Bool) -> [String] {
                var tokens: [String] = []
                var buffer = ""
                for chunk in chunks {
                    if buggy {
                        tokens += split(chunk)
                    } else {
                        buffer += chunk
                        var segments = split(buffer)
                        let partial = segments.removeLast()
                        tokens += segments
                        buffer = partial
                    }
                }
                return tokens
            }
        }
        """
        #expect(analyzeBooleanControlCoupling(source).isEmpty == false)
    }

    @Test func flagsBranchingInsideInitializer() {
        let source = """
        struct Engine {
            init(useFastPath: Bool) {
                if useFastPath {
                    configureFast()
                    warmCaches()
                } else {
                    configureSafe()
                    verifyInvariants()
                }
            }
        }
        """
        #expect(analyzeBooleanControlCoupling(source).isEmpty == false)
    }

    @Test func flagsNegatedCondition() {
        let source = """
        struct S {
            func run(skipValidation: Bool) {
                if !skipValidation {
                    validate()
                    record()
                } else {
                    proceed()
                    note()
                }
            }
        }
        """
        #expect(analyzeBooleanControlCoupling(source).isEmpty == false)
    }

    @Test func flagsCompoundCondition() {
        let source = """
        struct S {
            func run(verbose: Bool, ready: Bool) {
                if verbose && ready {
                    logDetailed()
                    flush()
                } else {
                    logTerse()
                    drop()
                }
            }
        }
        """
        #expect(analyzeBooleanControlCoupling(source).isEmpty == false)
    }

    @Test func flagsMultiStatementArmsWithoutCalls() {
        // Both arms have 2+ statements — substantial even without calls.
        let source = """
        struct S {
            func pick(advanced: Bool) -> Int {
                var result = 0
                if advanced {
                    result = 1
                    result += 10
                } else {
                    result = 2
                    result += 20
                }
                return result
            }
        }
        """
        #expect(analyzeBooleanControlCoupling(source).isEmpty == false)
    }

    @Test func flagsElseIfBranchOnFlag() {
        // The flag drives the inner if of an else-if chain.
        let source = """
        struct S {
            func handle(retry: Bool, code: Int) {
                if code == 0 {
                    succeed()
                } else if retry {
                    attemptAgain()
                    backOff()
                } else {
                    giveUp()
                    report()
                }
            }
        }
        """
        #expect(analyzeBooleanControlCoupling(source).isEmpty == false)
    }
}
