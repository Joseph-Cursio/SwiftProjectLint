import Foundation
import SwiftParser
@testable import SwiftProjectLintVisitors
import SwiftSyntax
import Testing

/// A kernel may hold another kernel, and the single-pass version could not see it.
///
/// `isPureKernel` is the discriminator `DirectInstantiation` and `ConcreteTypeUsage` both consult
/// before asking for a protocol seam (SwiftProjectLint#163). It admitted a type whose stored
/// properties are stdlib values or project enums, and refused one whose storage is a *project
/// struct* — however plainly that struct is itself a bag of values.
@Suite("Pure kernels resolve their storage to a fixpoint")
struct KernelStorageFixpointTests {

    private func catalog(_ source: String, enums: Set<String> = []) -> CleanInstanceMethodCatalog {
        CleanInstanceMethodCatalog.build(from: [Parser.parse(source: source)], enumTypes: enums)
    }

    /// The corpus shape, reduced: `EffectAnnotationParser` holds one `AttributeRecognition`, which
    /// is five `Set<String>`. Before the fixpoint the inner type was admitted and the outer one was
    /// not, so three findings across two rules asked for a protocol in front of a pure function.
    @Test func aKernelHoldingAKernelIsAKernel() {
        let source = """
        struct Recognition {
            let names: Set<String>
            func matches(_ name: String) -> Bool { names.contains(name) }
        }
        struct Parser {
            let recognition: Recognition
            func parse(_ text: String) -> Bool { recognition.matches(text) }
        }
        """
        let built = catalog(source)
        #expect(built.isPureKernel("Recognition"))
        #expect(built.isPureKernel("Parser"))
    }

    /// Three deep, because one extra pass would reach depth two and stop — the same reason
    /// `SendableProtocols` resolves its refinement set to a fixpoint rather than with two passes.
    @Test func transitivityIsNotDepthLimited() {
        let source = """
        struct Leaf { let values: Set<String> }
        struct Middle { let leaf: Leaf }
        struct Outer { let middle: Middle }
        struct Top { let outer: Outer }
        """
        let built = catalog(source)
        #expect(built.isPureKernel("Leaf"))
        #expect(built.isPureKernel("Top"))
    }

    // MARK: - What it must still refuse

    /// The direction that matters. `PluginPermissionGrantsStore` stores a `UserDefaults` and
    /// `PersistenceController` a SwiftData `ModelContainer`; both are real dependencies, and both
    /// were false exemptions when this test was written as a denylist. A type holding one of them
    /// must not become a kernel because the holder is otherwise tidy.
    @Test func holdingANonKernelIsNotAKernel() {
        let source = """
        struct GrantsStore { let defaults: UserDefaults }
        struct Manager { let store: GrantsStore }
        """
        let built = catalog(source)
        #expect(!built.isPureKernel("GrantsStore"))
        #expect(!built.isPureKernel("Manager"))
    }

    /// A `var` is state whatever it holds, so a kernel cannot hold a mutable kernel either.
    @Test func mutableStorageDisqualifiesHowevercleanItsTypeIs() {
        let source = """
        struct Leaf { let values: Set<String> }
        struct Holder { var leaf: Leaf }
        """
        #expect(!catalog(source).isPureKernel("Holder"))
    }

    /// The set starts empty and only grows, so a reference cycle never promotes. That is a refusal
    /// rather than a wrong answer, and it is the property that makes the loop safe to run to
    /// stability.
    @Test func aStorageCycleRefusesRatherThanLooping() {
        let source = """
        final class A { let b: B? = nil }
        final class B { let a: A? = nil }
        """
        let built = catalog(source)
        #expect(!built.isPureKernel("A"))
        #expect(!built.isPureKernel("B"))
    }

    /// Condition (1) is unchanged and still does most of the work: a type whose methods reach the
    /// file system is not a kernel however value-shaped its storage is.
    @Test func aDirtyMethodStillDisqualifies() {
        let source = """
        struct CacheManager {
            let root: URL
            func purge() throws { try FileManager.default.removeItem(at: root) }
        }
        """
        #expect(!catalog(source).isPureKernel("CacheManager"))
    }
}
