@testable import Core
import Testing

/// One input and what `NSString` answers for its last component, its parent and its stem.
struct PathComponentCase: Sendable {
    let input: String
    let last: String
    let parent: String
    let stem: String

    init(_ input: String, _ last: String, _ parent: String, _ stem: String) {
        self.input = input
        self.last = last
        self.parent = parent
        self.stem = stem
    }
}

/// A path, a component, and what `NSString.appendingPathComponent` answers for the pair.
struct PathAppendCase: Sendable {
    let path: String
    let component: String
    let expected: String

    init(_ path: String, _ component: String, _ expected: String) {
        self.path = path
        self.component = component
        self.expected = expected
    }
}

/// `PathString` replaced every `(path as NSString).…PathComponent` in the repo, so it owes
/// `NSString`'s answers. Each expected value below is what `NSString` returned for that input on
/// macOS 26 when the helpers were written, including the edge cases a hand-written split gets
/// wrong: repeated and trailing separators, `"/"` itself, the empty string, dot-files.
@Suite
struct PathStringTests {

    private static let componentCases: [PathComponentCase] = [
        PathComponentCase("", "", "", ""),
        PathComponentCase("/", "/", "/", "/"),
        PathComponentCase("//", "/", "/", "/"),
        PathComponentCase("a", "a", "", "a"),
        PathComponentCase("a/", "a", "", "a"),
        PathComponentCase("a//", "a", "", "a"),
        PathComponentCase("/a", "a", "/", "/a"),
        PathComponentCase("/a/", "a", "/", "/a"),
        PathComponentCase("/a/b", "b", "/a", "/a/b"),
        PathComponentCase("/a/b/", "b", "/a", "/a/b"),
        PathComponentCase("a//b", "b", "a", "a/b"),
        PathComponentCase("/a//b", "b", "/a", "/a/b"),
        PathComponentCase("./a", "a", ".", "./a"),
        PathComponentCase("../a", "a", "..", "../a"),
        PathComponentCase("a/.", ".", "a", "a/."),
        PathComponentCase("~", "~", "", "~"),
        PathComponentCase("/tmp/x.swift", "x.swift", "/tmp", "/tmp/x"),
        PathComponentCase("Foo.swift", "Foo.swift", "", "Foo"),
        PathComponentCase(".hidden", ".hidden", "", ".hidden"),
        PathComponentCase("a.b.c", "a.b.c", "", "a.b"),
        PathComponentCase("dir.d/file", "file", "dir.d", "dir.d/file"),
        PathComponentCase("dir.d/", "dir.d", "", "dir"),
        PathComponentCase("x.", "x.", "", "x."),
        PathComponentCase("/a.b/c", "c", "/a.b", "/a.b/c"),
        PathComponentCase("a/.swift", ".swift", "a", "a/.swift"),
    ]

    private static let appendCases: [PathAppendCase] = [
        PathAppendCase("", "x", "x"),
        PathAppendCase("/", "x", "/x"),
        PathAppendCase("/a", "x", "/a/x"),
        PathAppendCase("/a/", "x", "/a/x"),
        PathAppendCase("a", "", "a"),
        PathAppendCase("a", "/x", "a/x"),
        PathAppendCase("a/", "/x", "a/x"),
        PathAppendCase("/a//", "x", "/a/x"),
        PathAppendCase("a", "x/", "a/x"),
        PathAppendCase("a", "x//y", "a/x/y"),
        PathAppendCase("", "", ""),
        PathAppendCase("a//b", "c", "a/b/c"),
        PathAppendCase("/", "", "/"),
        PathAppendCase("/a", "../b", "/a/../b"),
        PathAppendCase("a", "Packages/Child", "a/Packages/Child"),
    ]

    private static let splitCases: [(String, [String])] = [
        ("", []),
        ("/", ["/"]),
        ("//", ["/", "/"]),
        ("a", ["a"]),
        ("a/", ["a", "/"]),
        ("/a", ["/", "a"]),
        ("/a/b", ["/", "a", "b"]),
        ("/a/b/", ["/", "a", "b", "/"]),
        ("a//b", ["a", "b"]),
        ("./a/./b", [".", "a", ".", "b"]),
        ("Sources/Tests/A.swift", ["Sources", "Tests", "A.swift"]),
    ]

    @Test("last component, parent and extension-less path match NSString", arguments: componentCases)
    func componentsMatchNSString(_ example: PathComponentCase) {
        #expect(PathString.lastComponent(of: example.input) == example.last)
        #expect(PathString.deletingLastComponent(of: example.input) == example.parent)
        #expect(PathString.deletingExtension(of: example.input) == example.stem)
    }

    @Test("appending a component matches NSString", arguments: appendCases)
    func appendingMatchesNSString(_ example: PathAppendCase) {
        #expect(PathString.appending(example.component, to: example.path) == example.expected)
    }

    @Test("splitting into components matches NSString", arguments: splitCases)
    func splittingMatchesNSString(input: String, expected: [String]) {
        #expect(PathString.components(of: input) == expected)
    }
}
