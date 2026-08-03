import Foundation
import PropertyBased
import SwiftParser
@testable import SwiftProjectLintConfig
@testable import SwiftProjectLintRules
import SwiftSyntax
import Testing

/// Laws for four `-> String?` extractors, written to test a claim rather than to add coverage.
///
/// The claim was mine: that the 254 seeds `DeclaredRoleClassifier` leaves unclassified "genuinely
/// owe nothing entailed", so the template catalog's silence on them is correct rather than a gap.
/// It was reached by reading shapes from a distance. A frozen sample of 20 `String?` extractors —
/// every third of 78, sorted by file:line, chosen before any was read — refuted it: nine had a law
/// worth writing. These are the four strongest.
///
/// Two of them were also unreachable (`private`) until this change, which is the advice the linter
/// now gives applied to itself: `balancedArgs` and `baseTypeName` were widened to `internal`, and
/// the duplicated string-literal readers were lifted into `StringLiteralValue` — the two remedies
/// `PureFunctionCandidateVisitor` names, one each.
@Suite("Extractor laws — from the frozen sample of twenty")
struct ExtractorLawsTests {

    // MARK: - 1. Unwrapping a type is invariant under wrapping

    /// `baseTypeName` strips `some` / `any` / `?` / `!` recursively.
    ///
    /// The law needs no name and no docstring: wrapping a type in any combination of those markers
    /// must not change the base name it resolves to. Refutable by any implementation that stops at
    /// the first layer, and the generator is a random tower of wrappers.
    @Test("wrapping a type in any combination of some/any/?/! leaves the base name unchanged")
    func baseTypeNameIgnoresWrappers() async {
        await propertyCheck(
            input: Self.baseNameGen, Self.wrappersGen, Self.prefixMarkerGen
        ) { base, wrappers, marker in
            // `some`/`any` bind outermost and cannot stack; optionals attach to the inner type.
            let text = marker + base + wrappers.joined()
            guard let type = Self.parseTypeAnnotation("let x: \(text) = y") else { return }
            #expect(DependencyConsumption.baseTypeName(type) == base,
                    "\(marker)\(base)\(wrappers.joined()) did not resolve to \(base)")
        }
    }

    // MARK: - 2. A balanced scan returns balanced text

    /// `balancedArgs` walks forward from just inside a `(` until depth returns to zero.
    ///
    /// Two laws, and the second is the one worth generating for: the result must itself be
    /// balanced, and the scan must **terminate without trapping** on any input — it advances with
    /// `content.index(after:)` inside a loop, which is where an off-by-one meets `endIndex`.
    @Test("what balancedArgs returns is itself balanced, and it never traps")
    func balancedArgsReturnsBalancedText() async {
        await propertyCheck(input: Self.parenCharsGen) { characters in
            let content = "f(" + characters.joined()
            guard let open = content.firstIndex(of: "(") else { return }
            let start = content.index(after: open)
            // Refusing is always allowed; returning something unbalanced is not.
            guard let extracted = ExecutableTargetDetector.balancedArgs(in: content, from: start) else {
                return
            }
            var depth = 0
            var wentNegative = false
            for character in extracted {
                if character == "(" { depth += 1 }
                if character == ")" { depth -= 1 }
                if depth < 0 { wentNegative = true }
            }
            #expect(wentNegative == false, "unbalanced result for \(content)")
            #expect(depth == 0, "unbalanced result for \(content)")
        }
    }

    // MARK: - 3 & 4. A string literal's value round-trips

    /// **The law that motivated the whole experiment.**
    ///
    /// For any string with no interpolation, building a literal from it and reading the value back
    /// must return the original. Two of the three security visitors implemented this by slicing
    /// `description` with `dropFirst().dropLast()`, which returns SOURCE TEXT: an escaped quote
    /// came back as `a\"b` rather than `a"b`. A security rule then silently stops matching.
    @Test("reading a literal's value round-trips through the source it was written as")
    func stringLiteralValueRoundTrips() async {
        await propertyCheck(input: Self.literalCharsGen) { characters in
            let original = characters.joined()
            let escaped = original
                .replacingOccurrences(of: "\\", with: "\\\\")
                .replacingOccurrences(of: "\"", with: "\\\"")
            guard let literal = Self.parseStringLiteral("let x = \"\(escaped)\"") else { return }
            #expect(StringLiteralValue.of(literal) == original,
                    "value did not round-trip for \(original.debugDescription)")
        }
    }

    /// Interpolation has no compile-time value, so the reader must refuse rather than invent one by
    /// joining the literal segments around the hole.
    @Test("an interpolated literal has no value")
    func interpolatedLiteralHasNoValue() async {
        await propertyCheck(input: Self.prefixGen, Self.suffixGen) { prefix, suffix in
            let source = "let x = \"\(prefix)\\(value)\(suffix)\""
            guard let literal = Self.parseStringLiteral(source) else { return }
            #expect(StringLiteralValue.of(literal) == nil, "invented a value for an interpolation")
        }
    }

    // MARK: - Generators and parsing helpers
    //
    // Hoisted out of the `propertyCheck` calls deliberately: inline, the parse chains and generator
    // compositions tripped "unable to type-check this expression in reasonable time". This project
    // has been bitten by that before, and a local build that merely takes a long time is a CI build
    // that fails outright.

    private static let baseNameGen = Gen<String?>
        .element(of: ["Foo", "Bar", "ServiceProtocol"]).map { $0 ?? "Foo" }
    /// Optionals only, and an opaque/existential marker chosen separately.
    ///
    /// The first version drew freely from `["?", "!", "some ", "any "]` and composed them in
    /// order, which builds text Swift does not accept — `any some T`, `some T?`. The parser's
    /// error recovery then produced a tree whose base name was literally `some`, and the property
    /// went red for the generator's fault rather than the function's. A generator that emits
    /// invalid inputs tests the parser, not the subject.
    private static let optionalMarkerGen = Gen<String?>
        .element(of: ["?", "!"]).map { $0 ?? "?" }
    private static let wrappersGen = optionalMarkerGen.array(of: 0...3)
    private static let prefixMarkerGen = Gen<String?>
        .element(of: ["", "some ", "any "]).map { $0 ?? "" }
    private static let parenCharGen = Gen<String?>
        .element(of: ["(", ")", "a", " ", ",", "\""]).map { $0 ?? "a" }
    private static let parenCharsGen = parenCharGen.array(of: 0...30)
    private static let literalCharGen = Gen<String?>
        .element(of: ["a", "Z", "1", "/", ":", "\"", "\\", " ", "-"]).map { $0 ?? "a" }
    private static let literalCharsGen = literalCharGen.array(of: 0...12)
    private static let prefixGen = Gen<String?>
        .element(of: ["prefix", "", "https://"]).map { $0 ?? "" }
    private static let suffixGen = Gen<String?>
        .element(of: ["suffix", "", "/path"]).map { $0 ?? "" }

    private static func parseTypeAnnotation(_ source: String) -> TypeSyntax? {
        let tree = Parser.parse(source: source)
        guard let item = tree.statements.first?.item else { return nil }
        guard let declaration = item.as(VariableDeclSyntax.self) else { return nil }
        return declaration.bindings.first?.typeAnnotation?.type
    }

    private static func parseStringLiteral(_ source: String) -> StringLiteralExprSyntax? {
        let tree = Parser.parse(source: source)
        guard let item = tree.statements.first?.item else { return nil }
        guard let declaration = item.as(VariableDeclSyntax.self) else { return nil }
        let value = declaration.bindings.first?.initializer?.value
        return value?.as(StringLiteralExprSyntax.self)
    }
}
