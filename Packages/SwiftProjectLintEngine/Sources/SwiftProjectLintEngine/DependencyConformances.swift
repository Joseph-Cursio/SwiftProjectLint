import Foundation

/// Which type names the project's **resolved SwiftPM dependencies** declare `Equatable` — read from
/// their checkouts, for the handful of names a remedy needs.
///
/// ## Why this exists
///
/// `EquatableRemedyCatalog` states a remedy only when every member of a type is comparable, and a
/// type the project does not declare used to block outright. That is right for a type nobody can
/// see and wrong for one sitting in `.build/checkouts`: SwiftLintRuleStudio's `YAMLConfig` stores
/// `[String: Node]`, Yams declares `public enum Node: Hashable`, and so
/// `MigrationAssistant.applyMigration(_:to: inout YAMLConfig)` — a pure mutator whose remedy is two
/// keywords — was never seeded.
///
/// ## What it reads, and how
///
/// - **Where:** `.build/checkouts/*` under the lint root, and under each directory directly below
///   it that holds a `Package.swift` — the local packages of an Xcode app. Xcode's own
///   `DerivedData/…/SourcePackages` is not read: which of its folders belongs to this project is a
///   guess, and a guess is not evidence. A dependency that has not been resolved is simply absent,
///   which is the behaviour before this existed.
/// - **Which modules:** only `Sources/<Module>` of a checkout, for a `<Module>` some project file
///   imports. A checkout holds more than its product: swift-syntax's `CodeGeneration` package
///   declares a `class Node`, and reading it made Yams' `Node` a namesake and vouched for neither.
///   A dependency laid out with a custom `path:` is not found this way, which loses a vouch and
///   never invents one.
/// - **What:** only files that mention one of the names asked about, so a large dependency such as
///   swift-syntax is skimmed rather than read. `Tests` folders, hidden directories and nested
///   `.build`s are skipped.
/// - **How:** a **text** scan of declaration headers, not a parse. A dependency is never linted, and
///   parsing it on a cooperative thread is what `LargeStackWorkers` exists to avoid — a deep
///   generated file overflows 512 KB. A header the scan cannot read is evidence of nothing.
///
/// ## When a name is vouched for
///
/// Exactly one primary declaration (`struct`/`enum`/`class`/`actor`) of the name across every
/// checkout read, not generic, with `Equatable`, `Hashable` or `Comparable` declared on it or on an
/// unconditional `extension`. Two declarations is a namesake the scan cannot tell apart; an
/// `extension … where …` is a conditional conformance and does not count.
enum DependencyConformances {

    /// The names among `names` that a resolved dependency of the project at `root` declares
    /// `Equatable`. Empty when `names` is, without touching the disk.
    static func equatableNames(
        among names: Set<String>,
        root: String,
        importedModules: Set<String>
    ) -> Set<String> {
        guard !names.isEmpty, !importedModules.isEmpty else { return [] }
        var declarations: [Declaration] = []
        for file in checkoutSources(root: root, modules: importedModules) {
            guard let text = try? String(contentsOf: file, encoding: .utf8),
                  names.contains(where: text.contains) else { continue }
            declarations += Self.declarations(in: text).filter { names.contains($0.name) }
        }
        return vouched(declarations)
    }

    /// One declaration header, as the scan read it.
    struct Declaration: Equatable {
        enum Kind: Equatable { case primary, unconditionalExtension, conditionalExtension }
        let kind: Kind
        /// The simple name: the last component of `Outer.Inner`.
        let name: String
        let isGeneric: Bool
        let conformances: Set<String>
    }

    private static let equatableConformances: Set<String> = ["Equatable", "Hashable", "Comparable"]

    /// The names the declarations vouch for — see the type's doc for the rule.
    static func vouched(_ declarations: [Declaration]) -> Set<String> {
        Set(Dictionary(grouping: declarations, by: \.name).compactMap { name, group in
            let primaries = group.filter { $0.kind == .primary }
            guard primaries.count == 1, primaries[0].isGeneric == false else { return nil }
            let declared = group.filter { $0.kind != .conditionalExtension }
                .reduce(into: Set<String>()) { $0.formUnion($1.conformances) }
            return declared.isDisjoint(with: equatableConformances) ? nil : name
        })
    }

    /// Every declaration header in `text`, comments removed first so a commented-out
    /// `extension Node: Equatable {}` is not read as one.
    static func declarations(in text: String) -> [Declaration] {
        let source = withoutComments(text)
        let range = NSRange(source.startIndex..., in: source)
        return headerPattern.matches(in: source, range: range).compactMap { match in
            guard let keyword = capture(1, of: match, in: source),
                  let path = capture(2, of: match, in: source),
                  let name = path.split(separator: ".").last.map(String.init) else { return nil }
            let generic = capture(3, of: match, in: source) != nil
            let clause = capture(4, of: match, in: source) ?? ""
            let (inherited, isConditional) = inheritance(clause)
            let kind: Declaration.Kind = keyword == "extension"
                ? (isConditional ? .conditionalExtension : .unconditionalExtension)
                : .primary
            return Declaration(kind: kind, name: name, isGeneric: generic, conformances: inherited)
        }
    }

    /// `struct|enum|class|actor|extension Name<…>: A, B where … {` — modifiers and attributes before
    /// the keyword are allowed and ignored, and the clause may span lines.
    private static let headerPattern: NSRegularExpression = {
        let pattern = #"(?m)^[ \t]*(?:@[\w.]+(?:\([^)\n]*\))?\s+)*"#
            + #"(?:(?:public|open|internal|package|fileprivate|private|final|indirect|nonisolated)\s+)*"#
            + #"(struct|enum|class|actor|extension)\s+([A-Za-z_][\w.]*)\s*(<[^>{]*>)?\s*(?::([^{]*))?\{"#
        // A literal pattern that does not compile is a programming error, caught by the tests.
        // swiftlint:disable:next force_try
        return try! NSRegularExpression(pattern: pattern)
    }()

    /// The inherited names in an inheritance clause, and whether a `where` makes it conditional.
    private static func inheritance(_ clause: String) -> (Set<String>, Bool) {
        let parts = clause.components(separatedBy: " where ")
        let isConditional = parts.count > 1 || clause.hasPrefix("where ")
        let names = parts[0].split(separator: ",").compactMap { entry -> String? in
            let trimmed = entry.trimmingCharacters(in: .whitespacesAndNewlines)
            // `@retroactive Equatable`, `Swift.Equatable`, `~Copyable`.
            let bare = trimmed.split(separator: " ").last.map(String.init) ?? trimmed
            return bare.split(separator: ".").last.map(String.init)
        }
        return (Set(names), isConditional)
    }

    private static func capture(_ index: Int, of match: NSTextCheckingResult, in text: String) -> String? {
        let range = match.range(at: index)
        guard range.location != NSNotFound, let swiftRange = Range(range, in: text) else { return nil }
        return String(text[swiftRange])
    }

    /// `text` with `//` and `/* */` comments blanked. String literals are not tracked: a `//` inside
    /// one blanks the rest of its line, which can only hide a header, never invent one.
    private static func withoutComments(_ text: String) -> String {
        let blocks = text.replacingOccurrences(of: #"/\*[\s\S]*?\*/"#, with: " ", options: .regularExpression)
        return blocks.replacingOccurrences(of: #"//[^\n]*"#, with: "", options: .regularExpression)
    }

    // MARK: - Finding the checkouts

    /// Every `.swift` file of `modules` in the checkouts the project at `root` resolved.
    static func checkoutSources(root: String, modules: Set<String>) -> [URL] {
        let fileManager = FileManager.default
        let rootURL = URL(fileURLWithPath: root)
        var packageDirectories = [rootURL]
        let children = (try? fileManager.contentsOfDirectory(
            at: rootURL, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles]
        )) ?? []
        packageDirectories += children.filter {
            fileManager.fileExists(atPath: $0.appendingPathComponent("Package.swift").path)
        }
        let checkouts = packageDirectories.flatMap { directory -> [URL] in
            (try? fileManager.contentsOfDirectory(
                at: directory.appendingPathComponent(".build/checkouts"),
                includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles]
            )) ?? []
        }
        return checkouts.flatMap { checkout in
            modules.sorted().flatMap { module in
                swiftFiles(under: checkout.appendingPathComponent("Sources/\(module)"), fileManager: fileManager)
            }
        }
    }

    /// The first component of every `import` in `texts` — `import Yams`, `@testable import X`,
    /// `import struct Foundation.Date`, `public import Y`. A text scan, for the reason the
    /// declarations are one.
    static func importedModules(in texts: [String]) -> Set<String> {
        var modules: Set<String> = []
        for text in texts {
            let range = NSRange(text.startIndex..., in: text)
            for match in importPattern.matches(in: text, range: range) {
                if let module = capture(1, of: match, in: text) { modules.insert(module) }
            }
        }
        return modules
    }

    private static let importPattern: NSRegularExpression = {
        let pattern = #"(?m)^[ \t]*(?:@[\w]+(?:\([^)\n]*\))?\s+)*"#
            + #"(?:(?:public|internal|package|fileprivate|private)\s+)?"#
            + #"import\s+(?:(?:struct|class|enum|protocol|typealias|func|var|let|actor)\s+)?([A-Za-z_]\w*)"#
        // swiftlint:disable:next force_try
        return try! NSRegularExpression(pattern: pattern)
    }()

    private static func swiftFiles(under directory: URL, fileManager: FileManager) -> [URL] {
        guard let walker = fileManager.enumerator(
            at: directory, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles]
        ) else { return [] }
        var files: [URL] = []
        for case let url as URL in walker {
            let name = url.lastPathComponent
            if name == "Tests" || name.hasSuffix("Tests") || name == ".build" || name.hasPrefix(".") {
                walker.skipDescendants()
                continue
            }
            if url.pathExtension == "swift", name != "Package.swift", !name.hasPrefix("Package@") {
                files.append(url)
            }
        }
        return files
    }
}
