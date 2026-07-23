import Foundation

/// Formatting for the "these types cluster together" findings, shared by the shape-clustering
/// rules (`DuplicateStructShape`, `SharedDomainEnumField`).
///
/// Peers are identified by **location**, not by name. Filtering peers by name — the form both
/// rules originally used — silently produced an *empty* peer list the moment two clustered types
/// shared a name (three visitors each with a private `TypeShape`, five with an `AnalysisSite`),
/// and a suggestion that read "conform Foo, Foo, Foo to it". That is exactly the case where the
/// reader most needs the other locations. `ParallelEnumShape` carries an equivalent fix inline;
/// it keeps its own message format and so does not route through here.
enum PeerLabeling {

    /// `'Name' (File.swift:line)` for every member except the one at `current`, sorted.
    static func peers(
        _ members: [(name: String, file: String, line: Int)],
        excluding current: (file: String, line: Int)
    ) -> String {
        members
            .filter { $0.file != current.file || $0.line != current.line }
            .map { "'\($0.name)' (\(($0.file as NSString).lastPathComponent):\($0.line))" }
            .sorted()
            .joined(separator: ", ")
    }

    /// Distinct member names, sorted — so a suggestion cannot read "conform Foo, Foo, Foo".
    static func distinctNames(_ names: [String]) -> String {
        Array(Set(names)).sorted().joined(separator: ", ")
    }
}
