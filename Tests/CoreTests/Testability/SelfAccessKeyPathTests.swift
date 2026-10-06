@testable import Core
import Foundation
import SwiftParser
import SwiftProjectLintVisitors
import SwiftSyntax
import Testing

/// A key-path component names a member of the key path's root type, not of `self`. The components
/// used to be collected as bare references, so `filter(\.isEnabled)` inside an instance method read
/// as `self.isEnabled` and refuted the method — and, through the clean-method catalog, every
/// sibling that called it.
@Suite
struct SelfAccessKeyPathTests {

    private func shape(_ source: String, method: String) -> PropertyTestShape? {
        let tree = Parser.parse(source: source)
        let finder = FunctionFinder(viewMode: .sourceAccurate)
        finder.walk(tree)
        guard let declaration = finder.found[method] else { return nil }
        return PropertyTestCandidacy.shape(
            of: declaration,
            knownEquatableTypes: ["String", "Int"],
            knownValueTypes: ["Engine"]
        )
    }

    // MARK: - Components are not reads of self

    @Test func aKeyPathPropertyComponentNoLongerRefutes() {
        let source = """
        struct Engine {
            func enabledCount(_ rules: [String: Rule]) -> Int {
                rules.filter(\\.value.enabled).count
            }
        }
        """
        #expect(shape(source, method: "enabledCount") == .ofInputs)
    }

    @Test func aKeyPathWithAnExplicitRootNoLongerRefutes() {
        let source = """
        struct Engine {
            func names(_ rules: [Rule]) -> String {
                rules.map(\\Rule.name).joined()
            }
        }
        """
        #expect(shape(source, method: "names") == .ofInputs)
    }

    @Test func aCalledKeyPathNoLongerRefutes() {
        // Without the experimental method-component feature, the parser reads `\\.uppercased()` as
        // a call applied to the property key path `\\.uppercased`; either way it is not `self`.
        let source = """
        struct Engine {
            func shout(_ words: [String]) -> String {
                words.map(\\.uppercased()).joined()
            }
        }
        """
        #expect(shape(source, method: "shout") == .ofInputs)
    }

    // MARK: - What still refutes

    @Test func aStoredPropertySharingAComponentsNameStillRefutesWhenReadDirectly() {
        // Only the component is skipped. The same name read as a bare identifier is still a read
        // of `self.enabled`, and a mutable one at that.
        let source = """
        struct Engine {
            var enabled = false
            func count(_ rules: [Rule]) -> Int {
                rules.filter(\\.enabled).count + (enabled ? 1 : 0)
            }
        }
        """
        #expect(shape(source, method: "count") == nil)
    }

    @Test func aSubscriptComponentsArgumentIsStillARead() {
        // `\\.[index]` reads `index`, and here `index` is mutable instance state.
        let source = """
        struct Engine {
            var index = 0
            func column(_ rows: [[Int]]) -> Int {
                rows.map(\\.[index]).count
            }
        }
        """
        #expect(shape(source, method: "column") == nil)
    }

    // MARK: - Callers

    @Test func aCallerOfAMethodUsingAKeyPathIsClearedToo() {
        // The shape of SwiftLintRuleStudio's `analyze` → `calculateBreakdown` →
        // `calculateRulesCoverage`: refusing the leaf used to refuse the whole chain.
        let source = """
        struct Engine {
            func report(_ rules: [String: Rule]) -> Int { breakdown(rules) }
            func breakdown(_ rules: [String: Rule]) -> Int { coverage(rules) * 2 }
            func coverage(_ rules: [String: Rule]) -> Int { rules.filter(\\.value.enabled).count }
        }
        """
        let clean = CleanInstanceMethodCatalog
            .build(from: [Parser.parse(source: source)])
            .cleanMethods(on: "Engine")
        #expect(clean == ["report", "breakdown", "coverage"])
    }

    final class FunctionFinder: SyntaxVisitor {
        var found: [String: FunctionDeclSyntax] = [:]
        override func visit(_ node: FunctionDeclSyntax) -> SyntaxVisitorContinueKind {
            found[node.name.text] = node
            return .visitChildren
        }
    }
}
