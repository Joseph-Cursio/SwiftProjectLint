@testable import Core
import PropertyBased
import Testing

/// Property-based laws for `FileAnalysisUtils.extractSwiftBasename(from:)`,
/// derived from its **docstring** rather than from its shape.
///
/// The function is `(String) -> String`, which on its own owes only
/// determinism — the non-refutable `f(x) == f(x)` that proposal-time scoring
/// exists to discount. Everything checkable here comes instead from the
/// sentence the author wrote:
///
/// > *"returns the base file name without its extension … derived from the file
/// > name by removing the `.swift` extension"*
///
/// That is a reference definition, and it is falsifiable: "the extension" is a
/// suffix, singular. The implementation was
/// `replacingOccurrences(of: ".swift", with: "")`, which removes **every**
/// occurrence anywhere in the name — so `"My.swiftUI.helper.swift"` came back as
/// `"MyUI.helper"`, silently corrupting the interior text.
///
/// The drift was found by writing the sentence down as a law, not by reading the
/// code, and it is the shape a purely structural catalog cannot name: a
/// formatter, a rounding mode and a suffix-strip are not round-trips, not
/// monoids and not idempotent-with-content — they are only ever wrong relative
/// to what they *said* they would do.
@Suite
struct BasenameExtractionLawsTests {

    /// Path segments built from a small alphabet that includes the dot and the
    /// separator, so `.swift` fragments recur inside names rather than only at
    /// the end. A wide alphabet essentially never generates the collision this
    /// law exists to find.
    private static let segmentGen = Gen<String?>
        .element(of: ["a", "b", ".", "swift", ".swift", "View", "-"])
        .map { $0 ?? "a" }
        .array(of: 1...5)
        .map { $0.joined() }

    /// **L9.1 — the ordinary case round-trips.** For a basename with no interior
    /// `".swift"`, appending the extension and extracting returns it unchanged.
    @Test
    func appendingTheExtensionThenExtractingIsTheIdentity() async {
        let plainGen = Gen<String?>.element(of: ["a", "b", "View", "Model", "-", "1"])
            .map { $0 ?? "a" }
            .array(of: 1...5)
            .map { $0.joined() }

        await propertyCheck(input: plainGen) { name in
            #expect(FileAnalysisUtils.extractSwiftBasename(from: name + ".swift") == name)
        }
    }

    /// **L9.2 — only the extension is removed.**
    ///
    /// The law the docstring states and the original implementation broke.
    /// Stated positively: extracting a basename removes exactly one trailing
    /// `".swift"`, so the result is the name with that suffix dropped and
    /// nothing else touched.
    @Test
    func onlyTheTrailingExtensionIsRemoved() async {
        await propertyCheck(input: Self.segmentGen) { stem in
            let fileName = stem + ".swift"
            let extracted = FileAnalysisUtils.extractSwiftBasename(from: fileName)

            #expect(
                extracted == stem,
                """
                Interior text was altered. Input '\(fileName)' produced \
                '\(extracted)', expected '\(stem)' — the docstring says the \
                *extension* is removed, which is a suffix, not every occurrence.
                """
            )
        }
    }

    /// A name that is not a Swift file is returned unchanged — there is no
    /// extension to remove.
    @Test
    func namesWithoutTheExtensionAreUnchanged() async {
        await propertyCheck(input: Self.segmentGen) { stem in
            // Only meaningful when the generated stem does not itself end in the
            // extension, which the alphabet can produce.
            guard stem.hasSuffix(".swift") == false else { return }
            #expect(FileAnalysisUtils.extractSwiftBasename(from: stem) == stem)
        }
    }

    /// **Not idempotent — and that is the correct behaviour.**
    ///
    /// This function is a one-shot suffix strip, not a normaliser, so applying
    /// it twice is meaningless: `"a.swift.swift"` → `"a.swift"` → `"a"`.
    ///
    /// Worth recording because of how the two laws behaved against the two
    /// implementations. `T -> T` idempotence is the only law this function's
    /// *shape* entails, and it is the law the suggestion engine proposed for it.
    /// Under the buggy `replacingOccurrences` implementation that law **held**
    /// (`"a.swift.swift"` → `"a"` → `"a"`); under the corrected one it **fails**.
    ///
    /// So the single shape-derived property available here did not merely fail
    /// to find the bug — it ratified it, and would have flagged the fix as the
    /// regression. The law that found the bug came from the docstring instead.
    /// That asymmetry is the argument for reading reference definitions out of
    /// prose rather than only off type signatures.
    @Test
    func extractionIsDeliberatelyNotIdempotent() {
        let once = FileAnalysisUtils.extractSwiftBasename(from: "a.swift.swift")
        #expect(once == "a.swift")
        #expect(FileAnalysisUtils.extractSwiftBasename(from: once) == "a")
    }

    /// **L9.4 — the result is a basename.** No path separators survive, in
    /// either the POSIX or the normalised Windows spelling.
    @Test
    func theResultIsAlwaysABasename() async {
        let separatorGen = Gen<String?>.element(of: ["/", "\\"]).map { $0 ?? "/" }

        await propertyCheck(input: Self.segmentGen, separatorGen) { name, separator in
            let path = ["Users", "project", "Sources"].joined(separator: separator)
                + separator + name + ".swift"
            let extracted = FileAnalysisUtils.extractSwiftBasename(from: path)

            #expect(extracted.contains("/") == false)
            #expect(extracted.contains("\\") == false)
            #expect(extracted == name)
        }
    }

    /// Concrete anchors, including the counterexample the property produced.
    @Test
    func documentedExamples() {
        #expect(FileAnalysisUtils.extractSwiftBasename(from: "/path/to/ContentView.swift") == "ContentView")
        #expect(FileAnalysisUtils.extractSwiftBasename(from: "ContentView.swift") == "ContentView")
        #expect(FileAnalysisUtils.extractSwiftBasename(from: "C:\\proj\\ContentView.swift") == "ContentView")
        // The regression: interior ".swift" must survive.
        #expect(FileAnalysisUtils.extractSwiftBasename(from: "My.swiftUI.helper.swift") == "My.swiftUI.helper")
        #expect(FileAnalysisUtils.extractSwiftBasename(from: "a.swift.swift") == "a.swift")
        // No extension: unchanged.
        #expect(FileAnalysisUtils.extractSwiftBasename(from: "README") == "README")
    }
}
