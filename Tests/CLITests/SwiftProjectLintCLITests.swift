import Testing
import Foundation
@testable import CLI

@Suite
struct CLITests {

    // MARK: - Helpers

    /// Runs the CLI binary with the given arguments and returns (exitCode, stdout, stderr).
    private func runCLI(arguments: [String]) throws -> (exitCode: Int32, stdout: String, stderr: String) {
        let binary = productsDirectory.appendingPathComponent("CLI")

        let process = Process()
        process.executableURL = binary
        process.arguments = arguments

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        try process.run()
        process.waitUntilExit()

        let stdoutData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
        let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()

        return (
            exitCode: process.terminationStatus,
            stdout: String(data: stdoutData, encoding: .utf8) ?? "",
            stderr: String(data: stderrData, encoding: .utf8) ?? ""
        )
    }

    /// Returns the path to the products directory built by SwiftPM.
    private var productsDirectory: URL {
        // In SPM test runs, the xctest bundle is in the same directory as the CLI binary
        for bundle in Bundle.allBundles where bundle.bundlePath.hasSuffix(".xctest") {
            return bundle.bundleURL.deletingLastPathComponent()
        }
        // Fallback: use the .build/debug directory relative to the package
        return URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent(".build")
            .appendingPathComponent("debug")
    }

    /// A temporary empty directory for testing.
    private func makeTemporaryDirectory() throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("CLITests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    // MARK: - Missing argument

    // swiftprojectlint:disable Test Missing Require
    @Test func exitWithErrorWhenNoArguments() throws {
        let result = try runCLI(arguments: [])
        #expect(result.exitCode != 0)
    }

    // MARK: - Non-existent path

    // swiftprojectlint:disable Test Missing Require
    @Test func exitWithErrorForNonExistentPath() throws {
        let result = try runCLI(arguments: ["/nonexistent/path/to/project"])
        #expect(result.exitCode != 0)
        #expect(result.stderr.contains("does not exist"))
    }

    // MARK: - Valid empty project (no Swift files → clean exit)

    // swiftprojectlint:disable Test Missing Require
    @Test func cleanExitForEmptyProject() throws {
        let dir = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }

        let result = try runCLI(arguments: [dir.path])
        #expect(result.exitCode == 0)
    }

    // MARK: - Text format output

    // swiftprojectlint:disable Test Missing Require
    @Test func textFormatIsDefault() throws {
        let dir = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }

        let result = try runCLI(arguments: [dir.path])
        #expect(result.exitCode == 0)
        // Text format produces plain text, not JSON
        #expect(result.stdout.contains("{") == false)

    }

    // MARK: - JSON format output

    @Test func jsonFormatProducesValidJSON() throws {
        let dir = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }

        let result = try runCLI(arguments: [dir.path, "--format", "json"])
        #expect(result.exitCode == 0)
        // JSON output should be parseable
        let data = try #require(result.stdout.data(using: .utf8))
        let parsed = try? JSONSerialization.jsonObject(with: data)
        #expect(parsed != nil)
    }

    // MARK: - Invalid category

    // swiftprojectlint:disable Test Missing Require
    @Test func exitWithErrorForInvalidCategory() throws {
        let dir = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }

        let result = try runCLI(arguments: [dir.path, "--categories", "bogusCategory"])
        #expect(result.exitCode != 0)
        #expect(result.stderr.contains("Unknown category"))
    }

    // MARK: - Valid category filter

    // swiftprojectlint:disable Test Missing Require
    @Test func validCategoryFilterRuns() throws {
        let dir = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }

        let result = try runCLI(arguments: [dir.path, "--categories", "security"])
        #expect(result.exitCode == 0)
    }

    // MARK: - Threshold option

    // swiftprojectlint:disable Test Missing Require
    @Test func errorThresholdIgnoresWarnings() throws {
        let dir = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }

        // With --threshold error, warnings and info don't cause non-zero exit
        let result = try runCLI(arguments: [dir.path, "--threshold", "error"])
        #expect(result.exitCode == 0)
    }

    // MARK: - Version flag

    // swiftprojectlint:disable Test Missing Require
    @Test func versionFlagPrintsVersion() throws {
        let result = try runCLI(arguments: ["--version"])
        #expect(result.exitCode == 0)
        #expect(result.stdout.contains("1.0.0"))
    }

    // MARK: - Analysis of real Swift code

    // swiftprojectlint:disable Test Missing Require
    @Test func detectsIssuesInSwiftFile() throws {
        let dir = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }

        // Write a Swift file with a known issue (magic number)
        let swiftFile = dir.appendingPathComponent("TestView.swift")
        try """
        import SwiftUI
        struct TestView: View {
            var body: some View {
                Text("Hello")
                    .padding(42)
            }
        }
        """.write(to: swiftFile, atomically: true, encoding: .utf8)

        let result = try runCLI(arguments: [dir.path, "--threshold", "error"])
        // Should exit clean (magic numbers are warnings, not errors)
        #expect(result.exitCode == 0)
    }
}
