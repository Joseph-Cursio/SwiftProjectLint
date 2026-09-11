import Foundation
import PropertyBased
@testable import SwiftProjectLintConfig
import Testing

/// The laws the Extractable Total Kernel finding predicted for this derivation: the round trip and
/// the idempotence of normalising. Both are stated over generated roots and paths, which is the point
/// of lifting the computation out of two directory walkers and a configuration pass — inside them it
/// could only be reached by building a real tree on disk.
@Suite
struct ProjectRelativePathLawTests {

    // MARK: - Generators

    /// Components that are awkward on purpose: spaces, dots, a leading dot, and a `..` that nothing
    /// here resolves. A generator of tidy identifiers would make every law pass for the wrong reason.
    private static let componentGen = Gen<String?>.element(of: [
        "Sources", "Tests", ".build", "a b", "..", ".", "x.swift", "Pods", "node_modules", "é"
    ]).compactMap(\.self)

    private static let relativeGen = componentGen
        .array(of: 1 ... 5)
        .map { RelativePath($0.joined(separator: "/")) }

    /// Roots spelled several ways, including with a trailing slash and as `/`, because the prefix
    /// arithmetic is where the hand-written copies differed.
    private static let rootGen = Gen<String?>.element(of: [
        "/projects/app", "/projects/app/", "/", "/a", "/a/b/c",
        "/Users/someone/My Project", "/nonexistent-root-\(UInt8.max)"
    ]).compactMap(\.self)

    // MARK: - Round trip

    /// **The round-trip law.** Rebuild the whole from the root and the derived part, and the
    /// derivation gives back what it started with.
    ///
    /// This is the law the unguarded `dropFirst(root.count + 1)` broke: it returns a string for every
    /// input, and for an input not under the root that string does not rebuild into anything.
    @Test func derivingThenRebuildingIsTheIdentity() async {
        await propertyCheck(
            input: Self.rootGen, Self.relativeGen
        ) { given, relative in
            let root = ProjectRoot(given)
            let absolute = root.absolutePath(of: relative)
            #expect(
                root.relativePath(of: absolute) == relative,
                "root=\(root.path) relative=\(relative.value)"
            )
        }
    }

    /// The other direction: rebuilding a derived part gives back the path it was derived from, for
    /// any path actually under the root.
    @Test func rebuildingADerivedPartGivesBackTheSamePath() async {
        await propertyCheck(
            input: Self.rootGen, Self.relativeGen
        ) { given, relative in
            let root = ProjectRoot(given)
            let absolute = root.absolutePath(of: relative)
            guard let derived = root.relativePath(of: absolute) else {
                Issue.record("a path built under the root must derive: \(absolute)")
                return
            }
            #expect(root.absolutePath(of: derived) == absolute)
        }
    }

    // MARK: - Idempotence

    /// **The idempotence law.** Canonicalising twice equals canonicalising once — including for a
    /// root that does not exist, where `realpath` fails and the input is kept.
    @Test func canonicalisingIsIdempotent() async {
        await propertyCheck(input: Self.rootGen) { given in
            let once = ProjectRoot(given)
            let twice = ProjectRoot(once.path)
            #expect(twice.path == once.path, "given=\(given)")
        }
    }

    /// Normalising a relative path is idempotent through its own spelling, which is what lets the
    /// round-trip law compare values rather than strings.
    @Test func normalisingARelativePathIsIdempotent() async {
        await propertyCheck(
            input: Self.componentGen.array(of: 0 ... 5).map { $0.joined(separator: "//") }
        ) { raw in
            let once = RelativePath(raw)
            #expect(RelativePath(once.value) == once, "raw=\(raw)")
        }
    }

    // MARK: - Totality

    /// **The refusal law, and the one the old code could not satisfy.** For *any* two strings the
    /// answer is either `nil` or a relative path that rebuilds — never a string that merely looks
    /// like one. `dropFirst` is total on a `String`, which is exactly why the defect was silent.
    ///
    /// **This law was first written as the identity on the item path, and the first run refuted it**:
    /// root `/` with item `/projects/app/` derives `projects/app`, which rebuilds as `/projects/app`.
    /// That is not a bug in the derivation — dropping a trailing separator is the normalisation the
    /// type exists to do, and the idempotence law above says so. Asserting the identity on the string
    /// asks the derivation to preserve a spelling it is supposed to discard.
    ///
    /// So the law is the weaker and true one: rebuilding is a **retraction**, and deriving a rebuilt
    /// path gives back the same relative path. Everything the strong form was meant to catch is still
    /// caught — an unguarded `dropFirst` produces a tail that rebuilds to a *different* path, which
    /// then derives to a *different* relative path — and the law no longer fails on a correct
    /// implementation.
    @Test func anItemIsEitherRefusedOrNormalisesStably() async {
        let anyPath = Gen<String?>.element(of: [
            "/projects/app/Sources/File.swift", "/projects/appendix/Other.swift",
            "/elsewhere/File.swift", "/", "", "/projects/app", "/projects/app/",
            "relative/not/absolute", "/a", "/projects/app/../app/Sources"
        ]).compactMap(\.self)

        await propertyCheck(input: Self.rootGen, anyPath) { given, itemPath in
            let root = ProjectRoot(given)
            guard let derived = root.relativePath(of: itemPath) else { return }
            let rebuilt = root.absolutePath(of: derived)
            #expect(
                root.relativePath(of: rebuilt) == derived,
                "root=\(root.path) item=\(itemPath) derived=\(derived.value) rebuilt=\(rebuilt)"
            )
        }
    }

    /// `/projects/appendix` is not under `/projects/app`, and the separator is the only thing that
    /// says so. This is the off-by-one the round-trip law exists to catch, pinned as an example
    /// because a reader should see the case the arithmetic turns on.
    @Test func aSiblingWithASharedNamePrefixIsNotUnderTheRoot() {
        let root = ProjectRoot("/projects/app")
        #expect(root.relativePath(of: "/projects/appendix/Other.swift") == nil)
        #expect(root.relativePath(of: "/projects/app/Other.swift")?.value == "Other.swift")
    }

    /// The root names itself, and both spellings of it agree.
    @Test func theRootDerivesToTheRootPath() {
        let root = ProjectRoot("/projects/app")
        #expect(root.relativePath(of: "/projects/app")?.isRoot == true)
        #expect(root.relativePath(of: "/projects/app/")?.isRoot == true)
        #expect(root.absolutePath(of: .root) == "/projects/app")
    }

    /// Components carry the three uses the call sites have, so none of them re-splits the string.
    @Test func componentsCarryTheNameTheDepthAndTheSearch() {
        let relative = RelativePath("Sources/.build/Deep")
        #expect(relative.lastComponent == "Deep")
        #expect(relative.depth == 3)
        #expect(relative.components.contains(".build"))
        #expect(RelativePath("").depth == 0)
        #expect(RelativePath("").lastComponent.isEmpty)
    }

    // MARK: - The planted violator

    /// The implementation that was at `FileAnalysisUtils.swift:196`, kept here so the laws above are
    /// shown to be worth having rather than asserted to be.
    ///
    /// ```swift
    /// let relativePath = String(itemURL.path.dropFirst(resolvedRootPath.count + 1))
    /// ```
    ///
    /// No guard, no way to report failure, and `dropFirst` is total on a `String` — so an item not
    /// under the root yields a tail of the wrong length instead of nothing.
    private static func unguardedDerivation(root: String, itemPath: String) -> RelativePath {
        RelativePath(String(itemPath.dropFirst(ProjectRoot(root).path.count + 1)))
    }

    /// **The retraction law refutes it, and that is the point of writing the law down.**
    ///
    /// `/projects/appendix/Other.swift` under root `/projects/app` is the case: 13 characters of root
    /// plus one separator drops `"/projects/app"` and the `e`, leaving `"ndix/Other.swift"`. That is
    /// not a relative path, it rebuilds to `/projects/app/ndix/Other.swift`, and it was then handed
    /// to `skippedDirectories` matching and the user's `excluded_paths` — where being wrong means an
    /// exclusion silently stops excluding.
    @Test func theUnguardedDerivationFailsTheRetractionLaw() {
        let root = ProjectRoot("/projects/app")
        let sibling = "/projects/appendix/Other.swift"

        let wrong = Self.unguardedDerivation(root: "/projects/app", itemPath: sibling)
        #expect(wrong.value == "ndix/Other.swift")
        #expect(root.absolutePath(of: wrong) == "/projects/app/ndix/Other.swift")

        // The kernel refuses instead, which is the whole difference.
        #expect(root.relativePath(of: sibling) == nil)
    }

    /// And it agrees with the kernel wherever the item really is under the root — which is why the
    /// defect survived: every path the walker actually produced was fine, so no example test that
    /// built a real tree would ever have reached it.
    @Test func theUnguardedDerivationAgreesOnItemsActuallyUnderTheRoot() async {
        await propertyCheck(input: Self.rootGen, Self.relativeGen) { given, relative in
            let root = ProjectRoot(given)
            let absolute = root.absolutePath(of: relative)
            guard !relative.isRoot, root.path != "/" else { return }
            #expect(Self.unguardedDerivation(root: given, itemPath: absolute) == relative)
        }
    }
}
