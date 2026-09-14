import Foundation
import SwiftProjectLintModels
import SwiftProjectLintVisitors
import SwiftSyntax

/// Detects String-backed Codable enums whose cases rely on implicit raw values.
///
/// A String-backed enum's synthesized `Codable` conformance encodes each case as its raw value,
/// and a case without an explicit raw value takes its own name. So the stored or transmitted
/// format of the enum *is* its case names: renaming `case inactive` to `case disabled` compiles
/// cleanly, passes every test that round-trips through the current code, and makes every value
/// already on disk or in a server response fail to decode. An explicit `= "inactive"` decouples
/// the Swift name from the wire format, which is the whole fix.
///
/// **Two fixes, because of SwiftLint.** An explicit raw value equal to the case name is exactly what
/// SwiftLint's default `redundant_string_enum_value` reports, so the suggestion also offers the
/// alternative that satisfies both tools: a test pinning the raw values, which fails on a rename.
///
/// **Codable is the scope, not all enums.** SwiftLint's opt-in `explicit_enum_raw_value` asks for
/// raw values everywhere, which is noise on enums that are never persisted. Conformance to
/// `Codable`, `Encodable` or `Decodable` — on the declaration, or through an extension in the same
/// file — is what says the raw value leaves the process.
///
/// Not reported:
/// - Test and fixture files. An enum round-tripped only inside a test run has no stored values to
///   break, and test targets are where most throwaway `Codable` enums live.
/// - An enum that implements `init(from:)` or `encode(to:)` itself, in its body or a same-file
///   extension. Its format is hand-written and may not use the raw value at all.
/// - Integer-backed enums. Their implicit values are ordinal, a different hazard (reordering rather
///   than renaming), and many of them are never meant to be stable.
/// - Conformance declared in another file or inherited through a refining protocol, which a
///   per-file syntactic pass cannot see.
///
/// Reported once per enum, at its name, listing the cases that need a value. Info rather than
/// warning: the defect is latent until someone renames a case, and a new warning-level rule would
/// fail the default CLI threshold on every existing codebase that has such an enum.
final class ImplicitCodableRawValueVisitor: BasePatternVisitor {

    private static let codableProtocols: Set<String> = ["Codable", "Encodable", "Decodable"]
    private static let listedCaseLimit = 3

    /// Enum names given a Codable conformance by an extension in this file, and enum names given a
    /// hand-written coding member by one.
    private var codableByExtension: Set<String> = []
    private var customCodingByExtension: Set<String> = []

    required init(pattern: SyntaxPattern, viewMode: SyntaxTreeViewMode = .sourceAccurate) {
        super.init(pattern: pattern, viewMode: viewMode)
    }

    override func visit(_ node: SourceFileSyntax) -> SyntaxVisitorContinueKind {
        let extensions = ExtensionFacts(viewMode: .sourceAccurate)
        extensions.walk(node)
        codableByExtension = extensions.codable
        customCodingByExtension = extensions.customCoding
        return .visitChildren
    }

    override func visit(_ node: EnumDeclSyntax) -> SyntaxVisitorContinueKind {
        guard isTestOrFixtureFile() == false else { return .skipChildren }
        let name = node.name.text
        let inherited = (node.inheritanceClause?.inheritedTypes ?? []).map { Self.lastComponent($0.type) }

        // Swift requires the raw type to come first in the inheritance clause.
        guard inherited.first == "String",
              inherited.contains(where: Self.codableProtocols.contains) || codableByExtension.contains(name),
              Self.declaresCustomCoding(node.memberBlock) == false,
              customCodingByExtension.contains(name) == false else {
            return .visitChildren
        }

        let implicit = Self.caseElements(in: node.memberBlock.members).filter { $0.rawValue == nil }
        guard let example = implicit.first else { return .visitChildren }

        // A backtick-escaped case (`` `default` ``) keeps its backticks as a name but not in its raw value.
        let rawValues = implicit.map { $0.name.text.trimmingCharacters(in: CharacterSet(charactersIn: "`")) }
        let listed = rawValues.prefix(Self.listedCaseLimit).map { "'\($0)'" }.joined(separator: ", ")
        let unlisted = rawValues.count - Self.listedCaseLimit
        let remainder = unlisted > 0 ? " and \(unlisted) more" : ""

        addIssue(
            severity: .info,
            message: "Codable enum '\(name)' uses implicit raw values for \(listed)\(remainder) — "
                + "renaming a case changes its encoded value",
            filePath: getFilePath(for: Syntax(node)),
            lineNumber: getLineNumber(for: Syntax(node.name)),
            suggestion: "Give each case an explicit raw value, e.g. `case \(example.name.text) = \"\(rawValues[0])\"`, "
                + "so a rename keeps the stored format — or, where SwiftLint's redundant_string_enum_value "
                + "forbids that, pin the raw values in a test.",
            ruleName: .implicitCodableRawValue
        )
        return .visitChildren
    }

    // MARK: - Helpers

    /// Case elements declared directly in the enum, including inside `#if` blocks.
    private static func caseElements(in members: MemberBlockItemListSyntax) -> [EnumCaseElementSyntax] {
        members.flatMap { member -> [EnumCaseElementSyntax] in
            if let caseDecl = member.decl.as(EnumCaseDeclSyntax.self) {
                return Array(caseDecl.elements)
            }
            guard let ifConfig = member.decl.as(IfConfigDeclSyntax.self) else { return [] }
            return ifConfig.clauses.flatMap { clause -> [EnumCaseElementSyntax] in
                guard case .decls(let nested)? = clause.elements else { return [] }
                return caseElements(in: nested)
            }
        }
    }

    static func declaresCustomCoding(_ memberBlock: MemberBlockSyntax) -> Bool {
        memberBlock.members.contains { member in
            if let initializer = member.decl.as(InitializerDeclSyntax.self) {
                return initializer.signature.parameterClause.parameters.first?.firstName.text == "from"
            }
            if let function = member.decl.as(FunctionDeclSyntax.self) {
                return function.name.text == "encode"
                    && function.signature.parameterClause.parameters.first?.firstName.text == "to"
            }
            return false
        }
    }

    /// `Codable` for `Swift.Codable`, `String` for `Swift.String`.
    static func lastComponent(_ type: TypeSyntax) -> String {
        if let member = type.as(MemberTypeSyntax.self) {
            return member.name.text
        }
        return type.trimmedDescription
    }
}

/// What the file's extensions add to an enum by name.
private final class ExtensionFacts: SyntaxVisitor {
    private(set) var codable: Set<String> = []
    private(set) var customCoding: Set<String> = []

    override func visit(_ node: ExtensionDeclSyntax) -> SyntaxVisitorContinueKind {
        let name = ImplicitCodableRawValueVisitor.lastComponent(node.extendedType)
        let inherited = (node.inheritanceClause?.inheritedTypes ?? [])
            .map { ImplicitCodableRawValueVisitor.lastComponent($0.type) }
        if inherited.contains(where: ["Codable", "Encodable", "Decodable"].contains) {
            codable.insert(name)
        }
        if ImplicitCodableRawValueVisitor.declaresCustomCoding(node.memberBlock) {
            customCoding.insert(name)
        }
        return .skipChildren
    }
}
