import Foundation

/// Just enough of Swift's lexical structure to read a `Package.swift` as text: comments,
/// string literals, bracket depth, top-level declarations and labeled arguments.
///
/// The manifest detectors read text rather than a syntax tree (see ``DefaultIsolationDetector``).
/// What text reading gets wrong is mostly comments and strings: a comment explaining why a target
/// *omits* `.defaultIsolation(MainActor.self)` still contains it, and a URL's `//` is not a
/// comment. So those two are handled properly, and the rest is bracket counting.
enum ManifestText {

    /// `source` without its `//` and `/* */` comments. String literals are kept whole.
    static func strippingComments(_ source: String) -> String {
        let chars = Array(source)
        var result: [Character] = []
        result.reserveCapacity(chars.count)
        var index = 0
        while index < chars.count {
            if chars[index] == "\"" {
                let end = endOfString(chars, from: index)
                result.append(contentsOf: chars[index..<end])
                index = end
            } else if hasPrefix(chars, "//", at: index) {
                while index < chars.count, chars[index] != "\n" { index += 1 }
            } else if hasPrefix(chars, "/*", at: index) {
                index = endOfBlockComment(chars, from: index)
                result.append(" ")
            } else {
                result.append(chars[index])
                index += 1
            }
        }
        return String(result)
    }

    /// Each top-level `let`/`var` with the text of its value, in source order. A value runs from
    /// its `=` to the next top-level statement. A declaration with no `=` before that statement
    /// is left out: `let dependencies: [Target.Dependency]`, assigned later inside an `#if`.
    static func topLevelDeclarations(in code: String) -> [(name: String, value: String)] {
        let chars = Array(code)
        let masked = maskingStrings(chars)
        let statements = topLevelStatements(in: masked)
        return statements.indices.compactMap { position in
            let statement = statements[position]
            guard statement.keyword == "let" || statement.keyword == "var" else { return nil }
            let end = position + 1 < statements.count ? statements[position + 1].start : chars.count
            guard let declaration = declarationStart(
                in: masked, from: statement.start + statement.keyword.count, to: end
            ) else { return nil }
            return (declaration.name, String(chars[declaration.valueStart..<end]))
        }
    }

    /// The text of the argument labeled `label` at the top level of `arguments` — the inside of
    /// one call's parentheses — up to the next top-level comma.
    static func argument(_ label: String, in arguments: String) -> String? {
        let chars = Array(arguments)
        let masked = maskingStrings(chars)
        let labelChars = Array(label)
        var depth = 0
        var index = 0
        while index < masked.count {
            if depth == 0, isWord(labelChars, in: masked, at: index),
               let colon = nextNonSpace(in: masked, from: index + labelChars.count), masked[colon] == ":" {
                let end = endOfArgument(masked, from: colon + 1)
                return String(chars[(colon + 1)..<end]).trimmingCharacters(in: .whitespacesAndNewlines)
            }
            depth += depthChange(masked[index])
            index += 1
        }
        return nil
    }

    /// The value of argument `label` when it is a plain string literal.
    static func stringArgument(_ label: String, in arguments: String) -> String? {
        guard let value = argument(label, in: arguments), value.count >= 2,
              value.hasPrefix("\""), value.hasSuffix("\""), value.hasPrefix("\"\"\"") == false else { return nil }
        let inner = String(value.dropFirst().dropLast())
        return inner.contains("\\(") || inner.contains("\"") ? nil : inner
    }

    // MARK: - Lexing

    /// `chars` with every string literal's contents (quotes included) replaced by spaces, so
    /// that brackets and keywords inside strings don't count. Indices are unchanged.
    private static func maskingStrings(_ chars: [Character]) -> [Character] {
        var masked = chars
        var index = 0
        while index < chars.count {
            guard chars[index] == "\"" else {
                index += 1
                continue
            }
            let end = endOfString(chars, from: index)
            for position in index..<end where chars[position] != "\n" {
                masked[position] = " "
            }
            index = end
        }
        return masked
    }

    /// The index just past the string literal opening at `start`.
    private static func endOfString(_ chars: [Character], from start: Int) -> Int {
        let isMultiline = hasPrefix(chars, "\"\"\"", at: start)
        var index = start + (isMultiline ? 3 : 1)
        while index < chars.count {
            if chars[index] == "\\" {
                index += 2
                continue
            }
            if isMultiline, hasPrefix(chars, "\"\"\"", at: index) {
                return index + 3
            }
            if isMultiline == false, chars[index] == "\"" || chars[index] == "\n" {
                return index + 1
            }
            index += 1
        }
        return chars.count
    }

    /// The index just past the block comment opening at `start`. Swift block comments nest.
    private static func endOfBlockComment(_ chars: [Character], from start: Int) -> Int {
        var depth = 0
        var index = start
        while index < chars.count {
            if hasPrefix(chars, "/*", at: index) {
                depth += 1
                index += 2
            } else if hasPrefix(chars, "*/", at: index) {
                depth -= 1
                index += 2
                if depth == 0 { return index }
            } else {
                index += 1
            }
        }
        return chars.count
    }

    private static let statementKeywords = [
        "let", "var", "func", "import", "for", "if", "guard", "while", "switch",
        "struct", "class", "enum", "extension", "#if"
    ]

    /// The statement keyword starting at `index`, if one does.
    private static func statementKeyword(in chars: [Character], at index: Int) -> String? {
        statementKeywords.first { isWord(Array($0), in: chars, at: index) }
    }

    /// Where each top-level statement starts, with its keyword, in source order.
    private static func topLevelStatements(in chars: [Character]) -> [(keyword: String, start: Int)] {
        var statements: [(keyword: String, start: Int)] = []
        var depth = 0
        for index in chars.indices {
            depth += depthChange(chars[index])
            if depth == 0, let keyword = statementKeyword(in: chars, at: index) {
                statements.append((keyword, index))
            }
        }
        return statements
    }

    /// The name declared after `let`/`var` and where its value starts, past the `=`. The name and
    /// the `=` are looked for only in `start..<end`, the rest of the statement, so the value never
    /// starts past the statement's end.
    private static func declarationStart(
        in chars: [Character], from start: Int, to end: Int
    ) -> (name: String, valueStart: Int)? {
        guard let nameStart = nextNonSpace(in: chars, from: start) else { return nil }
        var nameEnd = nameStart
        while nameEnd < end, isIdentifierCharacter(chars[nameEnd]) { nameEnd += 1 }
        guard nameEnd > nameStart else { return nil }
        var depth = 0
        for position in nameEnd..<end {
            depth += depthChange(chars[position])
            if depth == 0, chars[position] == "=", position + 1 < chars.count, chars[position + 1] != "=" {
                return (String(chars[nameStart..<nameEnd]), position + 1)
            }
            if depth == 0, chars[position] == "\n", position > nameEnd,
               chars[nameEnd..<position].contains(where: { $0 == ":" }) == false {
                return nil
            }
        }
        return nil
    }

    /// The index of the top-level comma ending the argument that starts at `start`, or the end.
    private static func endOfArgument(_ chars: [Character], from start: Int) -> Int {
        var depth = 0
        for index in start..<chars.count {
            if depth == 0, chars[index] == "," {
                return index
            }
            depth += depthChange(chars[index])
        }
        return chars.count
    }

    /// Whether `word` starts at `index` as a whole word.
    private static func isWord(_ word: [Character], in chars: [Character], at index: Int) -> Bool {
        guard hasPrefix(chars, word, at: index) else { return false }
        let before = index > 0 ? chars[index - 1] : " "
        let afterIndex = index + word.count
        let after = afterIndex < chars.count ? chars[afterIndex] : " "
        return isIdentifierCharacter(before) == false && before != "."
            && isIdentifierCharacter(after) == false
    }

    private static func nextNonSpace(in chars: [Character], from start: Int) -> Int? {
        chars[min(start, chars.count)...].firstIndex { $0.isWhitespace == false }
    }

    private static func depthChange(_ char: Character) -> Int {
        switch char {
        case "(", "[", "{": 1
        case ")", "]", "}": -1
        default: 0
        }
    }

    private static func isIdentifierCharacter(_ char: Character) -> Bool {
        char.isLetter || char.isNumber || char == "_"
    }

    private static func hasPrefix(_ chars: [Character], _ prefix: String, at index: Int) -> Bool {
        hasPrefix(chars, Array(prefix), at: index)
    }

    private static func hasPrefix(_ chars: [Character], _ prefix: [Character], at index: Int) -> Bool {
        index + prefix.count <= chars.count && Array(chars[index..<(index + prefix.count)]) == prefix
    }
}
