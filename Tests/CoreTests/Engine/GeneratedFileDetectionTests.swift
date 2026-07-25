import Foundation
import PropertyBased
@testable import SwiftProjectLintEngine
import Testing

/// Laws for `ProjectLinter.isGeneratedFile(at:)` — the gate that decides whether a file is skipped
/// entirely.
///
/// ## Why this one was missed
///
/// The second of the two candidates the road test's **hand-written answer key walked past** and the
/// toolchain surfaced. Its consequence is larger than its size: a false positive here means a
/// hand-written file is silently never linted, which is a confident zero with no output at all.
///
/// ## The reference definition is in the docstring
///
/// > *"Detection heuristics (any one suffices): File suffix `.pb.swift`, `.generated.swift`;
/// > Header comment: **first 5 lines** contain "DO NOT EDIT" or "Code generated".*
///
/// Two checkable claims — a suffix rule that needs no file at all, and a header rule with an
/// explicit five-line boundary. The boundary is the interesting half: it is a number in prose, and
/// nothing but a test holds the code to it.
@Suite
struct GeneratedFileDetectionTests {

    private func withTemporaryFile(
        named name: String,
        contents: String,
        _ body: (String) throws -> Void
    ) rethrows {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("GenFile-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent(name)
        try? contents.write(to: file, atomically: true, encoding: .utf8)
        try body(file.path)
    }

    private static let nameGen = Gen<String?>.element(of: ["a", "b", ".", "-", "Model"])
        .map { $0 ?? "a" }
        .array(of: 1...5)
        .map { $0.joined() }

    // MARK: - Totality

    /// A predicate owes an answer for every input, and this one is handed arbitrary paths from
    /// directory enumeration. A path that does not exist must be `false`, not a trap — the guard on
    /// `FileHandle(forReadingAtPath:)` is what makes that true, and it is one edit from becoming a
    /// force-unwrap.
    @Test
    func isTotalOverPathsThatDoNotExist() async {
        await propertyCheck(input: Self.nameGen) { name in
            #expect(ProjectLinter.isGeneratedFile(at: "/nonexistent/\(name).swift") == false)
        }
    }

    @Test
    func isTotalOverDegeneratePaths() {
        for path in ["", "/", ".", "..", "/dev/null", String(repeating: "x", count: 4_096)] {
            _ = ProjectLinter.isGeneratedFile(at: path)
        }
    }

    // MARK: - The suffix rule

    /// The suffix half needs no file on disk: the name alone decides. Refutable against an
    /// implementation that read the file first and returned `false` when it could not be opened —
    /// which would make generated-file detection depend on whether the scan can read the file, not
    /// on what it is.
    @Test
    func aGeneratedSuffixDecidesWithoutReadingTheFile() async {
        await propertyCheck(input: Self.nameGen) { stem in
            #expect(ProjectLinter.isGeneratedFile(at: "/nowhere/\(stem).pb.swift"))
            #expect(ProjectLinter.isGeneratedFile(at: "/nowhere/\(stem).generated.swift"))
        }
    }

    /// The suffix must be a *suffix*, not a substring. `Generated.swift` in the middle of a name is
    /// an ordinary hand-written file — `MyGeneratedThing.swift` is not generated.
    @Test
    func aSuffixLikeSubstringDoesNotCount() {
        #expect(ProjectLinter.isGeneratedFile(at: "/nowhere/My.generated.swiftUI.swift") == false)
        #expect(ProjectLinter.isGeneratedFile(at: "/nowhere/pb.swiftHelpers.swift") == false)
    }

    // MARK: - The header rule, and its stated boundary

    @Test(arguments: ["DO NOT EDIT", "Code generated"])
    func aMarkerInTheHeaderIsDetected(marker: String) {
        withTemporaryFile(named: "Plain.swift", contents: "// \(marker) — by a tool\nstruct S {}") {
            #expect(ProjectLinter.isGeneratedFile(at: $0))
        }
    }

    /// **The five-line boundary the docstring states.** A marker on line 5 counts; on line 6 it does
    /// not.
    ///
    /// This is the law worth the file. The number lives only in prose and in a `prefix(5)`, and the
    /// two can drift the moment someone reformats a header — in either direction, and both silently:
    /// widening it starts skipping hand-written files whose sixth line happens to mention code
    /// generation, narrowing it starts linting generated ones.
    @Test
    func theMarkerMustFallWithinTheFirstFiveLines() {
        let onFifth = (1...4).map { "// filler \($0)" }.joined(separator: "\n") + "\n// DO NOT EDIT\nstruct S {}"
        let onSixth = (1...5).map { "// filler \($0)" }.joined(separator: "\n") + "\n// DO NOT EDIT\nstruct S {}"

        withTemporaryFile(named: "Fifth.swift", contents: onFifth) {
            #expect(ProjectLinter.isGeneratedFile(at: $0), "a marker on line 5 is within the stated window")
        }
        withTemporaryFile(named: "Sixth.swift", contents: onSixth) {
            #expect(
                ProjectLinter.isGeneratedFile(at: $0) == false,
                "a marker on line 6 is outside the stated window"
            )
        }
    }

    /// An ordinary file is not generated, however long. Guards the direction that costs most: a
    /// false positive here means the file is never linted and nothing says so.
    @Test
    func anOrdinaryFileIsNotGenerated() {
        let source = """
        import Foundation

        /// A perfectly ordinary type.
        struct Widget {
            let identifier: String
        }
        """
        withTemporaryFile(named: "Widget.swift", contents: source) {
            #expect(ProjectLinter.isGeneratedFile(at: $0) == false)
        }
    }

    /// An empty file is readable and carries no marker — `false`, not a crash on the empty read.
    @Test
    func anEmptyFileIsNotGenerated() {
        withTemporaryFile(named: "Empty.swift", contents: "") {
            #expect(ProjectLinter.isGeneratedFile(at: $0) == false)
        }
    }
}
