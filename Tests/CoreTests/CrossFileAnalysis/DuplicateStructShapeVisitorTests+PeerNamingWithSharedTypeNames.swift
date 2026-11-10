@testable import Core
import Testing

extension DuplicateStructShapeVisitorTests {
    // MARK: - Peer naming with shared type names

    @Test("clustered structs that share a name still name each other by location")
    func sameNamedShapesReportLocationPeers() throws {
        // The regression: three visitors each with a private `TypeShape` of identical shape.
        // Filtering peers by name used to collapse to an empty peer list ("with  but no…")
        // and a "conform TypeShape, TypeShape, TypeShape" suggestion.
        let shape = "{ let name: String; let file: String; let line: Int; let extra: Bool }"
        let issues = duplicateStructShapeIssues(files: [
            "A.swift": "struct TypeShape \(shape)",
            "B.swift": "struct TypeShape \(shape)",
            "C.swift": "struct TypeShape \(shape)",
        ])
        #expect(issues.count == 3)

        let onA = try #require(issues.first { $0.filePath == "A.swift" })
        // Peers are the other two files, not an empty string.
        #expect(onA.message.contains("B.swift"))
        #expect(onA.message.contains("C.swift"))
        #expect(onA.message.contains("with  ") == false)

        // The suggestion lists the name once, not three times.
        let suggestion = try #require(onA.suggestion)
        #expect(suggestion.contains("TypeShape, TypeShape") == false)
    }

    @Test("differently-named clustered structs still report each name")
    func distinctlyNamedShapesUnaffected() throws {
        let shape = "{ let alpha: Int; let bravo: Int; let charlie: Int; let delta: Int }"
        let issues = duplicateStructShapeIssues(files: [
            "A.swift": "struct Foo \(shape)",
            "B.swift": "struct Bar \(shape)",
        ])
        #expect(issues.count == 2)
        let onFoo = try #require(issues.first { $0.filePath == "A.swift" })
        #expect(onFoo.message.contains("Bar"))
        #expect(onFoo.suggestion?.contains("Bar") == true)
        #expect(onFoo.suggestion?.contains("Foo") == true)
    }
}
