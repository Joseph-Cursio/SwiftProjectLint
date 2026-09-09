@testable import Core
import Foundation
import SwiftParser
@testable import SwiftProjectLintRules
import SwiftProjectLintVisitors
import SwiftSyntax
import Testing

/// A type that is already a seam must not be asked to become one.
///
/// Two shapes, both of which the rule used to report and both of which its own exemptions already
/// covered in another spelling.
///
/// **A value type whose whole content is one closure** is the nominal form of a function
/// `typealias`, which this rule has exempted for a while. `struct DateProvider { let make: () ->
/// Date }` is substituted by writing `DateProvider { fixedInstant }`. Worse than merely redundant:
/// `DateProvider` and `IDProvider` *exist because* `Non-Injected Nondeterminism` reported the
/// inline clock and id reads they replaced, so reporting them asks a reader to undo a repair the
/// same sweep asked for, one run apart.
///
/// **A `private` or `fileprivate` type** cannot be substituted at all: no caller outside the file
/// can name it, so a protocol around it could only be conformed to in that same file. Taking the
/// advice means *widening* the access level in order to abstract it. `DirectInstantiation` — this
/// rule's twin, firing on the same seam from the construction site — has had that exemption since
/// the shape was found there, and the two now share the walk that finds it.
@Suite("A type that is already a seam is not asked to become one")
struct ConcreteTypeUsageSeamTests {

    private func issues(
        _ source: String,
        wrappers: ClosureWrapperTypeCatalog = .empty,
        localTypes: Set<String> = [],
        equatableTypes: Set<String> = []
    ) -> [LintIssue] {
        let visitor = ConcreteTypeUsageVisitor(patternCategory: .architecture)
        visitor.knownClosureWrapperTypes = wrappers
        visitor.knownLocalTypeNames = localTypes
        visitor.knownEquatableTypes = equatableTypes
        let syntax = Parser.parse(source: source)
        visitor.setSourceLocationConverter(
            SourceLocationConverter(fileName: "Subject.swift", tree: syntax)
        )
        visitor.setFilePath("Subject.swift")
        visitor.walk(syntax)
        return visitor.detectedIssues.filter { $0.ruleName == RuleIdentifier.concreteTypeUsage }
    }

    /// The closure-wrapper catalog one source file yields.
    private func catalog(_ source: String) -> ClosureWrapperTypeCatalog {
        let parsed = [Parser.parse(source: source)]
        return ClosureWrapperTypeCatalog.build(from: parsed)
    }

    // MARK: - The closure wrapper

    private let providerSource = """
    struct DateProvider: Sendable {
        private let make: @Sendable () -> Date
        init(_ make: @escaping @Sendable () -> Date) { self.make = make }
        static let system = Self { Date() }
        var now: Date { make() }
    }

    final class Analyzer {
        let now: DateProvider
        init(now: DateProvider) { self.now = now }
    }
    """

    @Test("a property typed with a closure wrapper is not reported")
    func closureWrapperIsNotReported() {
        let built = catalog(providerSource)
        #expect(built.contains("DateProvider"))
        #expect(issues(providerSource, wrappers: built).isEmpty)
    }

    @Test("without the catalog the same property fires, which is the defect")
    func withoutTheCatalogItFires() {
        // The control, and what every run before this one did. A test asserting a filtered list is
        // empty passes for any reason, including a visitor that reported nothing at all.
        let found = issues(providerSource)
        #expect(found.count == 1)
        #expect(found.first?.message.contains("DateProvider") == true)
    }

    @Test("a static factory and a computed property do not disqualify a wrapper")
    func factoriesAndComputedPropertiesAreNotStorage() {
        // `static let system` is a factory over the type, not its content, and `var now: Date`
        // is the wrapper's whole point. Counting either as a stored property would have made
        // every real instance of this shape fail to qualify — which is exactly what a first,
        // cruder version of the detector did.
        let built = catalog(providerSource)
        #expect(built.contains("DateProvider"))
    }

    @Test("two closures is not a wrapper")
    func twoClosuresIsNotAWrapper() {
        // Deliberately strict: two closures is a small protocol wearing a struct, and the advice
        // starts being worth hearing again.
        let built = catalog("""
        struct EditingService: Sendable {
            let load: @Sendable () -> Data
            let save: @Sendable (Data) -> Void
        }
        """)
        #expect(!built.contains("EditingService"))
    }

    @Test("a struct holding a value is not a wrapper")
    func aValueHolderIsNotAWrapper() {
        let built = catalog("""
        struct SnapshotManager { let root: URL }
        """)
        #expect(!built.contains("SnapshotManager"))
    }

    @Test("a non-final class is not a wrapper")
    func openClassIsNotAWrapper() {
        // A subclass is a substitution route of its own, so the exemption — which is about types
        // offering no route but the closure — does not apply.
        let built = catalog("""
        class DiffLoader { let load: () -> Data }
        """)
        #expect(!built.contains("DiffLoader"))
    }

    // MARK: - The file-local type

    @Test("a private type is not reported")
    func privateTypeIsNotReported() {
        // `ToolInvocation`'s accumulator, reduced. No caller outside this file can name `Builder`,
        // so a protocol around it has nowhere to be conformed to.
        #expect(issues("""
        struct ToolInvocation {
            private struct Builder {
                var target: String?
                var outputPath: String?
            }
            private init(builder: Builder) throws { }
        }
        """).isEmpty)
    }

    @Test("the declaration may follow the use")
    func declarationMayFollowTheUse() {
        // The reason this is a pre-pass rather than bookkeeping as the walk goes: the parameter
        // is read before the declaration that exempts it.
        #expect(issues("""
        struct Owner {
            private init(builder: Builder) throws { }
        }

        private struct Builder {
            var target: String?
        }
        """).isEmpty)
    }

    @Test("an internal type of the same shape is still reported")
    func internalTypeIsStillReported() {
        // The control. Drop `private` and the advice becomes reachable again — a caller in another
        // file can name the type, so a protocol has somewhere to be conformed to.
        let found = issues("""
        struct Owner {
            init(builder: Builder) throws { }
        }

        struct Builder {
            var target: String?
        }
        """)
        #expect(found.count == 1)
        #expect(found.first?.message.contains("Builder") == true)
    }

    // MARK: - The platform framework type

    @Test("an AppKit or UIKit class is not reported")
    func platformFrameworkTypeIsNotReported() {
        // `LiveMarkdownTextEditor.Coordinator`, reduced: the parameter list of an
        // `NSLayoutManagerDelegate` requirement, which is not the author's to change.
        #expect(issues("""
        final class Coordinator: NSObject, NSLayoutManagerDelegate {
            func layoutManager(_ manager: NSLayoutManager, shouldGenerateGlyphs count: Int) -> Int {
                count
            }
        }
        """).isEmpty)

        // And `CameraView`, whose `updateUIViewController` is a `UIViewControllerRepresentable`
        // requirement — same impossibility, a different protocol.
        #expect(issues("""
        struct CameraView: UIViewControllerRepresentable {
            func updateUIViewController(_ picker: UIImagePickerController, context: Context) { }
        }
        """).isEmpty)
    }

    @Test("a project type with a platform prefix is still reported")
    func locallyDeclaredPrefixedTypeIsStillReported() {
        // The declaration decides, not the spelling. A project writing its own `UIStateManager`
        // keeps the finding, which is why the gate consults `knownLocalTypeNames` rather than
        // trusting two letters.
        let found = issues("""
        final class Screen {
            let state: UIStateManager
            init(state: UIStateManager) { self.state = state }
        }
        """, localTypes: ["UIStateManager"])
        #expect(found.count == 1)
        #expect(found.first?.message.contains("UIStateManager") == true)
    }

    @Test("a CoreLocation-shaped prefix is not treated as a platform type")
    func twoLetterPrefixCollisionIsPinned() {
        // The obvious generalisation of this gate — every Apple two-letter prefix — is refuted by
        // this corpus. `CLIToolCommandRunner` is `CL` followed by an uppercase letter and has
        // nothing to do with CoreLocation; a wider prefix set would silence it for a reason
        // unrelated to why it should be silent. Pinned so widening cannot happen quietly.
        let found = issues("""
        final class Bridge {
            let bridgedRunner: CLIToolCommandRunner
            init(bridgedRunner: CLIToolCommandRunner) { self.bridgedRunner = bridgedRunner }
        }
        """)
        #expect(found.count == 1)
        #expect(found.first?.message.contains("CLIToolCommandRunner") == true)
    }

    // MARK: - The value record

    @Test("an Equatable type is a value, not a dependency")
    func equatableTypeIsNotReported() {
        // `EnumCaseGenerator` describes an enum case and generates nothing; it is caught by the
        // suffix list and by nothing else. A value is substituted by constructing a different
        // one, which is what its memberwise initializer is for.
        #expect(issues("""
        struct Derivation {
            func render(enumCase: EnumCaseGenerator) -> String { "" }
        }
        """, equatableTypes: ["EnumCaseGenerator"]).isEmpty)
    }

    @Test("a non-Equatable type of the same name is still reported")
    func nonEquatableIsStillReported() {
        // The control. Nothing in the corpus that is genuinely a dependency conforms to
        // `Equatable` — a service is identified, not compared — so the conformance is the whole
        // of the signal and its absence has to restore the finding.
        let found = issues("""
        struct Derivation {
            func render(enumCase: EnumCaseGenerator) -> String { "" }
        }
        """)
        #expect(found.count == 1)
        #expect(found.first?.message.contains("EnumCaseGenerator") == true)
    }
}
