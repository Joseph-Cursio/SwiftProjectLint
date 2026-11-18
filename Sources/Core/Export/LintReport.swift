/// Top-level JSON report structure.
public struct LintReport: Codable, Sendable {
    /// The version of this report's shape. It changes whenever a field is
    /// added, removed or changes meaning.
    public static let currentSchemaVersion = 1

    /// The report's shape: `currentSchemaVersion` when written.
    public let schemaVersion: Int
    /// The tool and release that wrote the report.
    public let tool: ToolInfo
    public let summary: ReportSummary
    public let issues: [CodableLintIssue]

    public init(summary: ReportSummary, issues: [CodableLintIssue]) {
        self.schemaVersion = Self.currentSchemaVersion
        self.tool = ToolInfo(name: "SwiftProjectLint", version: SwiftProjectLintVersion.current)
        self.summary = summary
        self.issues = issues
    }
}

/// The tool that wrote a report.
public struct ToolInfo: Codable, Sendable {
    /// The tool's name.
    public let name: String
    /// Its release, `SwiftProjectLintVersion.current`.
    public let version: String
}
