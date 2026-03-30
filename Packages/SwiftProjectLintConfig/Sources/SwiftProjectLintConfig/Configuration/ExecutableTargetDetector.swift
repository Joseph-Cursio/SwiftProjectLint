import SwiftProjectLintModels
import Foundation

/// Parses `Package.swift` to identify source directories belonging to executable targets.
///
/// Used to suppress rules that don't apply to CLI programs — for example, `print()`
/// is the correct output mechanism in an executable and should not be flagged.
///
/// Handles both the default source convention (`Sources/<name>/`) and targets with
/// an explicit `path:` parameter.
public struct ExecutableTargetDetector {

    /// Returns source-relative path prefixes for all executable targets declared in
    /// `Package.swift` at the given project root.
    ///
    /// Example return value: `["Sources/swift-assist-cli/", "Sources/tool/"]`
    public static func executableSourcePaths(in projectRoot: String) -> [String] {
        let packagePath = (projectRoot as NSString).appendingPathComponent("Package.swift")
        guard let content = try? String(contentsOfFile: packagePath) else { return [] }
        return parseExecutableTargets(from: content)
    }

    private static func parseExecutableTargets(from content: String) -> [String] {
        guard let markerRegex = try? NSRegularExpression(
            pattern: #"\.executableTarget\s*\("#
        ) else { return [] }

        let matches = markerRegex.matches(
            in: content,
            range: NSRange(content.startIndex..., in: content)
        )

        return matches.compactMap { match -> String? in
            guard let matchRange = Range(match.range, in: content) else { return nil }

            // Scan from the opening '(' (included in the regex) to its matching ')'.
            let argsStart = matchRange.upperBound
            guard let argsBlock = balancedArgs(in: content, from: argsStart) else { return nil }

            guard let name = extractStringParam("name", from: argsBlock) else { return nil }

            if let explicitPath = extractStringParam("path", from: argsBlock) {
                return explicitPath.hasSuffix("/") ? explicitPath : explicitPath + "/"
            }
            return "Sources/\(name)/"
        }
    }

    // MARK: - Private helpers

    /// Returns the substring of `content` between the already-consumed opening `(`
    /// and its matching `)`, by counting paren depth.
    private static func balancedArgs(in content: String, from start: String.Index) -> String? {
        var depth = 1
        var pos = start
        while pos < content.endIndex, depth > 0 {
            switch content[pos] {
            case "(": depth += 1
            case ")": depth -= 1
            default: break
            }
            if depth > 0 { pos = content.index(after: pos) }
        }
        guard depth == 0 else { return nil }
        return String(content[start..<pos])
    }

    /// Extracts the string value of a named parameter (e.g., `name: "foo"`) from an
    /// argument block string.
    private static func extractStringParam(_ param: String, from block: String) -> String? {
        guard let regex = try? NSRegularExpression(
            pattern: #"\b"# + NSRegularExpression.escapedPattern(for: param) + #"\s*:\s*"([^"]+)""#
        ),
        let match = regex.firstMatch(
            in: block, range: NSRange(block.startIndex..., in: block)
        ),
        let valueRange = Range(match.range(at: 1), in: block) else { return nil }
        return String(block[valueRange])
    }
}
