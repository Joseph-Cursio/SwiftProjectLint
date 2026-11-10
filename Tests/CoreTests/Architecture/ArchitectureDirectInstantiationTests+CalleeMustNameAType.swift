@testable import Core
import Foundation
import Testing

extension ArchitectureDirectInstantiationTests {
    // MARK: - Callee must name a type

    @Test func testStaticMemberCallIsNotAnInstantiation() {
        // `DerivationStrategist.composedGenerator(forTypeName:)` is a `static func` returning a
        // value. The suffix test used to run against the whole callee text, so the *member's*
        // name ending in "Generator" was read as a type name and the finding read "direct
        // instantiation of 'DerivationStrategist.composedGenerator' — prefer dependency
        // injection", naming something that does not exist and cannot be injected.
        let source = """
        func resolve() {
            let result = DerivationStrategist.composedGenerator(forTypeName: name)
        }
        """
        let issues = analyzeSource(source).filter { $0.ruleName == .directInstantiation }
        #expect(issues.isEmpty)
    }

    @Test func testModuleQualifiedConstructionIsStillReported() throws {
        // The other half of the same change: dropping every member access would go too far,
        // because `Module.Type()` is an ordinary construction written with a qualifier.
        let source = """
        func boot() {
            let svc = Networking.NetworkService()
        }
        """
        let issues = analyzeSource(source).filter { $0.ruleName == .directInstantiation }
        let issue = try #require(issues.first)
        #expect(issue.message.contains("NetworkService"))
    }

    @Test func testGenericSpecializationIsStillReported() throws {
        let source = """
        func boot() {
            let svc = NetworkService<Int>()
        }
        """
        let issues = analyzeSource(source).filter { $0.ruleName == .directInstantiation }
        let issue = try #require(issues.first)
        #expect(issue.message.contains("NetworkService"))
    }

    // MARK: - File-local types cannot be injected

    @Test func testPrivateTypeIsNotReported() {
        // A `private` type is unreachable outside the file that declares it, so there is no
        // caller that could supply a substitute. Taking the advice would mean widening the
        // access level in order to hide the type — exporting an implementation detail to make
        // it injectable.
        let source = """
        enum AmbientStateReads {
            static func occur(in node: Syntax) -> Bool {
                let checker = Checker(viewMode: .sourceAccurate)
                checker.walk(node)
                return checker.sawSource
            }

            private final class Checker: SyntaxVisitor {
                var sawSource = false
            }
        }
        """
        let issues = analyzeSource(source).filter { $0.ruleName == .directInstantiation }
        #expect(issues.isEmpty)
    }

    @Test func testFileprivateTypeIsNotReported() {
        let source = """
        func isTotal(_ syntax: Syntax) -> Bool {
            let checker = TotalityChecker()
            checker.walk(syntax)
            return checker.isTotal
        }

        fileprivate final class TotalityChecker: SyntaxVisitor {
            var isTotal = true
        }
        """
        let issues = analyzeSource(source).filter { $0.ruleName == .directInstantiation }
        #expect(issues.isEmpty)
    }

    @Test func testDeclarationAfterUseIsStillSeen() {
        // The reason the access level is read in a pre-pass rather than as the walk goes: the
        // construction usually comes first. `AmbientStateReads.occur` builds its `Checker`
        // eight lines above the `private final class Checker` that declares it.
        let source = """
        func query(_ node: Syntax) -> Bool {
            let checker = LocalChecker()
            return checker.result
        }

        private final class LocalChecker {
            var result = false
        }
        """
        let issues = analyzeSource(source).filter { $0.ruleName == .directInstantiation }
        #expect(issues.isEmpty)
    }

    @Test func testNonPrivateTypeInTheSameFileIsStillReported() throws {
        // The gate is about reachability, not about locality. An `internal` type declared in
        // the same file *can* be named — and substituted — by any other file in the module.
        let source = """
        func query(_ node: Syntax) -> Bool {
            let checker = SharedChecker()
            return checker.result
        }

        final class SharedChecker {
            var result = false
        }
        """
        let issues = analyzeSource(source).filter { $0.ruleName == .directInstantiation }
        let issue = try #require(issues.first)
        #expect(issue.message.contains("SharedChecker"))
    }

    // MARK: - Test doubles

    @Test func testMockTypeIsNotReported() {
        // A double is already the substitute an injection would supply. `ConcreteTypeUsage` —
        // the rule that counts the same seam from the declaration end — has exempted these
        // since its own correction; this rule never had the vocabulary, so `MockGenerator` was
        // exempt where it was declared and reported where it was built.
        let source = """
        func lift() {
            let generator = MockGenerator(typeName: name)
        }
        """
        let issues = analyzeSource(source).filter { $0.ruleName == .directInstantiation }
        #expect(issues.isEmpty)
    }
}
