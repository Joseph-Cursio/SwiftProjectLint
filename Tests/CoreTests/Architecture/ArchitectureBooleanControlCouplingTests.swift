@testable import Core
import Foundation
import SwiftParser
@testable import SwiftProjectLintRules
import SwiftSyntax
import Testing

@Suite
struct ArchitectureBooleanControlCouplingTests {

    // MARK: - Helper

    private func analyzeSource(
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

    // MARK: - Violations

    @Test func flagsTwoCallPathsGatedOnBoolParameter() throws {
        let source = """
        struct Checkout {
            func price(isPremium: Bool) -> Int {
                if isPremium {
                    return premiumPrice()
                } else {
                    return standardPrice()
                }
            }
        }
        """
        let issues = analyzeSource(source)
        let issue = try #require(issues.first)
        #expect(issue.message.contains("isPremium"))
    }

    @Test func flagsBranchingInsideInitializer() throws {
        let source = """
        struct Engine {
            init(useFastPath: Bool) {
                if useFastPath {
                    configureFast()
                } else {
                    configureSafe()
                }
            }
        }
        """
        #expect(analyzeSource(source).isEmpty == false)
    }

    @Test func flagsNegatedCondition() throws {
        let source = """
        struct S {
            func run(skipValidation: Bool) {
                if !skipValidation {
                    validate()
                } else {
                    proceed()
                }
            }
        }
        """
        #expect(analyzeSource(source).isEmpty == false)
    }

    @Test func flagsCompoundCondition() throws {
        let source = """
        struct S {
            func run(verbose: Bool, ready: Bool) {
                if verbose && ready {
                    logDetailed()
                } else {
                    logTerse()
                }
            }
        }
        """
        #expect(analyzeSource(source).isEmpty == false)
    }

    @Test func flagsMultiStatementArmsWithoutCalls() throws {
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
        #expect(analyzeSource(source).isEmpty == false)
    }

    @Test func flagsElseIfBranchOnFlag() throws {
        // The flag drives the inner if of an else-if chain.
        let source = """
        struct S {
            func handle(retry: Bool, code: Int) {
                if code == 0 {
                    succeed()
                } else if retry {
                    attemptAgain()
                } else {
                    giveUp()
                }
            }
        }
        """
        #expect(analyzeSource(source).isEmpty == false)
    }

    // MARK: - Non-violations

    @Test func ignoresBoolParameterStoredNotBranched() {
        let source = """
        struct S {
            var enabled: Bool
            init(enabled: Bool) {
                self.enabled = enabled
            }
        }
        """
        #expect(analyzeSource(source).isEmpty)
    }

    @Test func ignoresOptionalBehaviorWithoutElse() {
        // `if verbose { log() }` is optional embellishment, not two strategies.
        let source = """
        struct S {
            func run(verbose: Bool) {
                doWork()
                if verbose {
                    log()
                }
            }
        }
        """
        #expect(analyzeSource(source).isEmpty)
    }

    @Test func ignoresBooleanToValueMapping() {
        // Each arm returns a single literal/value — a bool→value map, not control coupling.
        let source = """
        struct S {
            func color(isError: Bool) -> String {
                if isError {
                    return "red"
                } else {
                    return "green"
                }
            }
        }
        """
        #expect(analyzeSource(source).isEmpty)
    }

    @Test func ignoresOverriddenFunction() {
        // The signature is inherited and can't be changed freely.
        let source = """
        class Child: Parent {
            override func render(animated: Bool) {
                if animated {
                    animateIn()
                } else {
                    snapIn()
                }
            }
        }
        """
        #expect(analyzeSource(source).isEmpty)
    }

    @Test func ignoresNonBooleanParameter() {
        let source = """
        struct S {
            func run(mode: Int) {
                if mode == 1 {
                    fast()
                } else {
                    slow()
                }
            }
        }
        """
        #expect(analyzeSource(source).isEmpty)
    }

    @Test func ignoresMemberAccessSharingParameterName() {
        // `config.flag` must not match a parameter named `flag`.
        let source = """
        struct S {
            func run(flag: Bool) {
                if config.flag {
                    pathA()
                } else {
                    pathB()
                }
            }
        }
        """
        #expect(analyzeSource(source).isEmpty)
    }

    @Test func ignoresStdlibCapacityConventionFlag() {
        // `keepCapacity` mirrors `removeAll(keepingCapacity:)` — exempt even
        // though it branches two ways.
        let source = """
        struct Buffer {
            func removeAll(keepCapacity: Bool) {
                if keepCapacity {
                    zeroOut()
                    retainStorage()
                } else {
                    deallocate()
                    resetCount()
                }
            }
        }
        """
        #expect(analyzeSource(source).isEmpty)
    }

    @Test func ignoresCapacityConventionByArgumentLabel() {
        // The convention lives on the label; the internal name differs but is
        // still exempt.
        let source = """
        struct Buffer {
            func clear(keepingCapacity keep: Bool) {
                if keep {
                    zeroOut()
                    retainStorage()
                } else {
                    deallocate()
                    resetCount()
                }
            }
        }
        """
        #expect(analyzeSource(source).isEmpty)
    }

    @Test func ignoresTestAndFixtureFiles() {
        let source = """
        struct S {
            func price(isPremium: Bool) -> Int {
                if isPremium {
                    return premiumPrice()
                } else {
                    return standardPrice()
                }
            }
        }
        """
        #expect(analyzeSource(source, filePath: "PricingTests.swift").isEmpty)
    }
}
