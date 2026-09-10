@testable import Core
import Foundation
import SwiftParser
@testable import SwiftProjectLintRules
import SwiftSyntax
import Testing

/// Drives one of the two closure rules over `source`.
///
/// At file scope for the reason the census suite's helper is: it keeps the suite body inside
/// `type_body_length` as tests accumulate.
private func analyze(
    _ source: String,
    rule: RuleIdentifier = .impureClosureInventory,
    filePath: String = "Logic.swift",
    projectFunctions: Set<String> = []
) -> [LintIssue] {
    let syntax = Parser.parse(source: source)
    let issues: [LintIssue]
    if rule == .impureClosureInventory {
        let visitor = ImpureClosureVisitor(patternCategory: .testability)
        visitor.knownProjectFunctions = projectFunctions
        visitor.setSourceLocationConverter(SourceLocationConverter(fileName: filePath, tree: syntax))
        visitor.setFilePath(filePath)
        visitor.walk(syntax)
        issues = visitor.detectedIssues
    } else {
        let visitor = PureClosureCandidateVisitor(patternCategory: .testability)
        visitor.knownProjectFunctions = projectFunctions
        visitor.setSourceLocationConverter(SourceLocationConverter(fileName: filePath, tree: syntax))
        visitor.setFilePath(filePath)
        visitor.walk(syntax)
        issues = visitor.detectedIssues
    }
    return issues.filter { $0.ruleName == rule }
}

/// **The complement the tool computed on every run and threw away.**
///
/// The census reports the closures a purity oracle accepts; the ones it refuses were dropped without
/// a word, so the published number was an inventory of what is *already* testable and the list of
/// obstacles — the half a reader acts on — existed nowhere. SwiftProjectLint#186.
///
/// These tests are about the **witness** as much as the firing. A finding that says *this closure is
/// impure* and not what makes it so is a number, not a work list, and the number was already
/// available by subtraction.
@Suite("Impure closures are the inventory of what blocks a property test")
struct ImpureClosureVisitorTests {

    // MARK: - Each cause, named

    @Test("an effect in the closure is reported with the marker that found it")
    func sideEffectNamesItsMarker() {
        let issues = analyze("""
        func audit() {
            let flagged = files.filter { file in
                print(file.path)
                return file.size > limit && file.isStale
            }
        }
        """)
        #expect(issues.count == 1)
        #expect(issues.first?.message.contains("`print`") == true, "\(issues.first?.message ?? "")")
        #expect(issues.first?.suggestion?.contains("decision") == true)
    }

    @Test("a clock read is reported as nondeterminism, not as a side effect")
    func clockReadIsNondeterminism() {
        let issues = analyze("""
        func stale() {
            let expired = files.filter { file in
                let now = Date()
                return file.expiry < now
            }
        }
        """)
        #expect(issues.count == 1)
        #expect(issues.first?.message.contains("inputs do not determine") == true)
        #expect(issues.first?.message.contains("`Date`") == true, "\(issues.first?.message ?? "")")
        #expect(issues.first?.suggestion?.contains("Inject the source") == true)
    }

    @Test("a trap is reported as partiality, and names which trap")
    func trapIsPartiality() {
        let issues = analyze("""
        func names() {
            let sorted = files.sorted { lhs, rhs in
                if lhs.rank != rhs.rank { return lhs.rank! < rhs.rank! }
                return lhs.name < rhs.name
            }
        }
        """)
        #expect(issues.count == 1)
        #expect(issues.first?.message.contains("partial") == true)
        #expect(issues.first?.message.contains("force unwrap") == true, "\(issues.first?.message ?? "")")
    }

    /// The one cause whose advice is *take no action*. A census that could not say so would be
    /// pushing readers to "fix" closures that are already correct.
    @Test("a captured write names the capture, and the advice is to do nothing")
    func capturedWriteAdvisesNothing() {
        let issues = analyze("""
        func total() {
            let sizes = files.map { file in
                running += file.size
                return file.size
            }
        }
        """)
        #expect(issues.count == 1)
        #expect(issues.first?.message.contains("`running`") == true, "\(issues.first?.message ?? "")")
        #expect(issues.first?.suggestion?.hasPrefix("Nothing") == true, "\(issues.first?.suggestion ?? "")")
    }

    @Test("a throwing closure is reported on its signature alone")
    func declaredEffectIsReported() {
        let issues = analyze("""
        func parsed() {
            let values = rows.map { (row: Row) throws -> Int in
                let trimmed = row.text.trimmingCharacters(in: .whitespaces)
                return Int(trimmed) ?? 0
            }
        }
        """)
        #expect(issues.count == 1)
        #expect(issues.first?.message.contains("`throws`") == true, "\(issues.first?.message ?? "")")
    }

    // MARK: - Controls

    /// Without this the suite passes just as well when the rule fires on everything.
    @Test("a pure closure is not in the inventory")
    func pureClosureIsNotReported() {
        #expect(analyze("""
        func children() {
            let immediate = files.filter { file in
                let relative = file.path.replacingOccurrences(of: parent, with: "")
                return relative.split(separator: "/").count <= 1
            }
        }
        """).isEmpty)
    }

    @Test("a test file is skipped, like the census")
    func testFilesAreSkipped() {
        #expect(analyze("""
        func audit() {
            let flagged = files.filter { file in
                print(file.path)
                return file.size > limit && file.isStale
            }
        }
        """, filePath: "LogicTests.swift").isEmpty)
    }

    /// It is a census, not a seed. `CandidateInventory` and `PBTSeedsFormatter` list the rules a
    /// downstream tool may point analysis at, and this is not among them — a finding carrying a
    /// `role` is how it would leak into one.
    @Test("a finding carries no seed role")
    func findingsAreNotSeeds() {
        let issues = analyze("""
        func audit() {
            let flagged = files.filter { file in
                print(file.path)
                return file.size > limit && file.isStale
            }
        }
        """)
        #expect(issues.count == 1)
        #expect(issues.first?.role == nil)
    }

    // MARK: - The partition, which is the whole design claim

    /// **The two rules partition one population, and this is what says so.**
    ///
    /// The inventory is only readable against the census if they run the same gate — the same
    /// higher-order call sites, the same "hides a law worth stating" filter, the same forwarding
    /// check. Two rules each holding their own copy of that answer is the shape this project has
    /// found four times in the architecture rules, so the vocabulary was lifted into
    /// `CollectionOperation` *before* the second consumer was written, and this pins the
    /// result.
    ///
    /// Both halves are asserted. **Disjoint**: no closure is reported by both, which would mean the
    /// oracle disagreed with itself. **Complete**: the six qualifying closures below are all
    /// accounted for, which is what fails if one rule's gate drifts and starts admitting fewer call
    /// sites than the other's.
    @Test("every qualifying closure is in exactly one of the two rules")
    func theTwoRulesPartitionTheSamePopulation() {
        let source = """
        func mixed() {
            let a = files.filter { file in
                let relative = file.path.replacingOccurrences(of: parent, with: "")
                return relative.split(separator: "/").count <= 1
            }
            let b = files.filter { file in
                print(file.path)
                return file.isStale
            }
            let c = files.sorted { lhs, rhs in
                if lhs.isFolder != rhs.isFolder { return lhs.isFolder }
                return lhs.name < rhs.name
            }
            let d = files.sorted { lhs, rhs in
                if lhs.rank != rhs.rank { return lhs.rank! < rhs.rank! }
                return lhs.name < rhs.name
            }
            let e = files.map { file in
                let trimmed = file.name.trimmingCharacters(in: .whitespaces)
                return trimmed.lowercased()
            }
            let f = files.map { file in
                running += file.size
                return file.size
            }
        }
        """
        let pure = Set(analyze(source, rule: .pureClosureCandidate).map(\.lineNumber))
        let impure = Set(analyze(source, rule: .impureClosureInventory).map(\.lineNumber))

        #expect(pure.isDisjoint(with: impure), "a closure in both rules: \(pure.intersection(impure))")
        #expect(pure.count == 3, "expected a, c, e to be pure — got lines \(pure.sorted())")
        #expect(impure.count == 3, "expected b, d, f to be impure — got lines \(impure.sorted())")
        #expect(pure.union(impure).count == 6, "the shared gate admits six closures here")
    }
}
