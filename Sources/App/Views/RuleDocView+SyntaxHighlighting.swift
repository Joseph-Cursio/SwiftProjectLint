//
//  RuleDocView+SyntaxHighlighting.swift
//  SwiftProjectLint
//
//  Syntax highlighting for Swift code blocks in rule documentation.
//  Color palette matches SwiftLintRuleStudio.
//

import SwiftUI

extension RuleDocView {

    // MARK: - Color palette

    struct SyntaxColors {
        let keyword: Color
        let type: Color
        let string: Color
        let number: Color
        let comment: Color
        let attribute: Color

        static func colors(for colorScheme: ColorScheme) -> SyntaxColors {
            colorScheme == .dark ? .dark : .light
        }

        static let light = SyntaxColors(
            keyword: Color(hex: "#AD3DA4"),
            type: Color(hex: "#0B4F79"),
            string: Color(hex: "#D12F1B"),
            number: Color(hex: "#1C00CF"),
            comment: Color(hex: "#707F8C"),
            attribute: Color(hex: "#6C36A9")
        )

        static let dark = SyntaxColors(
            keyword: Color(hex: "#FF7AB2"),
            type: Color(hex: "#6BDFFF"),
            string: Color(hex: "#FC6A5D"),
            number: Color(hex: "#D0BF69"),
            comment: Color(hex: "#7F8C98"),
            attribute: Color(hex: "#CC85D6")
        )
    }

    // MARK: - Public entry point

    func highlightedCode(_ code: String, colorScheme: ColorScheme) -> AttributedString {
        let colors = SyntaxColors.colors(for: colorScheme)
        var result = AttributedString()
        let lines = code.components(separatedBy: "\n")

        for (idx, line) in lines.enumerated() {
            result.append(highlightLine(line, colors: colors))
            if idx < lines.count - 1 {
                result.append(AttributedString("\n"))
            }
        }

        return result
    }

    // MARK: - Line highlighting

    private func highlightLine(_ line: String, colors: SyntaxColors) -> AttributedString {
        // Whole-line comment
        if line.trimmingCharacters(in: .whitespaces).hasPrefix("//") {
            var attr = AttributedString(line)
            attr.foregroundColor = colors.comment
            attr.font = .system(.callout, design: .monospaced).italic()
            return attr
        }
        return tokenizeLine(line, colors: colors)
    }

    // MARK: - Greedy tokenizer

    private static let keywords = [
        "import", "class", "struct", "enum", "protocol",
        "extension", "func", "var", "let", "static",
        "private", "public", "internal", "fileprivate",
        "open", "mutating", "nonmutating", "override",
        "final", "lazy", "weak", "unowned", "typealias",
        "associatedtype", "init", "deinit", "subscript",
        "if", "else", "guard", "switch", "case", "default",
        "for", "while", "repeat", "do", "try", "catch",
        "throw", "throws", "rethrows", "async", "await",
        "return", "break", "continue", "fallthrough",
        "where", "in", "as", "is", "self", "Self", "super",
        "nil", "true", "false", "some", "any", "inout",
        "convenience", "required", "optional", "indirect",
        "get", "set", "willSet", "didSet", "defer",
        "precondition", "assert", "nonisolated",
        "consuming", "borrowing", "sending"
    ]

    private static let types = [
        "String", "Int", "Double", "Float", "Bool",
        "Character", "Void", "Array", "Dictionary", "Set",
        "Optional", "Result", "Error", "Any", "AnyObject",
        "AnyHashable", "Never", "URL", "Data", "Date",
        "UUID", "Codable", "Hashable", "Equatable",
        "Comparable", "Identifiable", "Sendable",
        "ObservableObject", "Published", "StateObject",
        "ObservedObject", "EnvironmentObject", "State",
        "Binding", "Environment", "View", "Scene", "App",
        "Text", "Image", "Button", "List",
        "NavigationView", "NavigationStack",
        "VStack", "HStack", "ZStack",
        "Int8", "Int16", "Int32", "Int64",
        "UInt", "UInt8", "UInt16", "UInt32", "UInt64",
        "CGFloat", "CGPoint", "CGSize", "CGRect", "NSObject"
    ]

    private static let keywordPattern =
        #"\b("# + keywords.joined(separator: "|") + #")\b"#
    private static let typePattern =
        #"\b("# + types.joined(separator: "|") + #")\b"#

    private func tokenizeLine(_ line: String, colors: SyntaxColors) -> AttributedString {
        // Patterns in priority order: earlier patterns win when ranges overlap.
        let patterns: [(String, Color, Bool)] = [
            // (pattern, color, isComment)
            (#""[^"\n]*""#, colors.string, false),
            (#"@[A-Za-z_][A-Za-z0-9_]*"#, colors.attribute, false),
            (Self.keywordPattern, colors.keyword, false),
            (Self.typePattern, colors.type, false),
            (#"\b\d[\d_.]*\b"#, colors.number, false),
            (#"//.*$"#, colors.comment, true)
        ]

        var result = AttributedString()
        var remaining = line[...]

        while !remaining.isEmpty {
            var bestRange: Range<String.Index>?
            var bestColor = Color.primary
            var bestIsComment = false
            var bestStart = remaining.endIndex

            for (pattern, color, isComment) in patterns {
                guard let range = remaining.range(
                    of: pattern, options: .regularExpression
                ) else { continue }
                if range.lowerBound < bestStart {
                    bestStart = range.lowerBound
                    bestRange = range
                    bestColor = color
                    bestIsComment = isComment
                }
            }

            guard let matchRange = bestRange else {
                result.append(AttributedString(String(remaining)))
                break
            }

            // Plain text before the token
            if matchRange.lowerBound > remaining.startIndex {
                let plain = String(remaining[remaining.startIndex..<matchRange.lowerBound])
                result.append(AttributedString(plain))
            }

            // Colored token
            var token = AttributedString(String(remaining[matchRange]))
            token.foregroundColor = bestColor
            if bestIsComment {
                token.font = .system(.callout, design: .monospaced).italic()
            }
            result.append(token)

            remaining = remaining[matchRange.upperBound...]
        }

        return result
    }
}

// MARK: - Color from hex

private extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        let scanner = Scanner(string: hex)
        var rgb: UInt64 = 0
        scanner.scanHexInt64(&rgb)
        let red   = Double((rgb >> 16) & 0xFF) / 255
        let green = Double((rgb >>  8) & 0xFF) / 255
        let blue  = Double( rgb        & 0xFF) / 255
        self.init(red: red, green: green, blue: blue)
    }
}
