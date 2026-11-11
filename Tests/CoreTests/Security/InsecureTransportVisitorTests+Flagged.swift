import SwiftParser
import SwiftProjectLintModels
@testable import SwiftProjectLintRules
import SwiftProjectLintVisitors
import SwiftSyntax
import Testing

extension InsecureTransportVisitorTests {
    // MARK: - Flagged: other insecure schemes

    @Test func testFlagsFTP() {
        let issues = issues(for: """
        let server = "ftp://files.mycompany.com/uploads"
        """)
        #expect(issues.count == 1)
    }

    @Test func testFlagsTelnet() {
        let issues = issues(for: """
        let remote = "telnet://admin.internal:23"
        """)
        #expect(issues.count == 1)
    }

    @Test func testFlagsMQTT() {
        let issues = issues(for: """
        let broker = "mqtt://iot.myservice.com:1883/topic"
        """)
        #expect(issues.count == 1)
    }

    @Test func testFlagsAMQP() {
        let issues = issues(for: """
        let queue = "amqp://mq.internal:5672/vhost"
        """)
        #expect(issues.count == 1)
    }

    @Test func testFlagsRedis() {
        let issues = issues(for: """
        let cache = "redis://cache.internal:6379/0"
        """)
        #expect(issues.count == 1)
    }

    @Test func testFlagsLDAP() {
        let issues = issues(for: """
        let directory = "ldap://ad.corp.internal:389/dc=example,dc=com"
        """)
        #expect(issues.count == 1)
    }

    @Test func testDoesNotFlagSecureVariants() {
        let issues = issues(for: """
        let one = "sftp://files.mycompany.com/uploads"
        let two = "ssh://admin.internal"
        let three = "mqtts://iot.myservice.com:8883/topic"
        let four = "amqps://mq.internal:5671/vhost"
        let five = "rediss://cache.internal:6380/0"
        let six = "ldaps://ad.corp.internal:636/dc=example,dc=com"
        """)
        #expect(issues.isEmpty)
    }

    @Test func testSuppressesFTPLocalhost() {
        let issues = issues(for: """
        let local = "ftp://localhost/files"
        """)
        #expect(issues.isEmpty)
    }

    // MARK: - Not flagged: secure schemes and non-URL strings

    @Test func testDoesNotFlagHTTPS() {
        let issues = issues(for: """
        let endpoint = "https://api.myservice.com/v1/users"
        """)
        #expect(issues.isEmpty)
    }

    @Test func testDoesNotFlagNonURLString() {
        let issues = issues(for: """
        let greeting = "hello world"
        """)
        #expect(issues.isEmpty)
    }

    @Test func testDoesNotFlagHTTPSubstring() {
        let issues = issues(for: """
        let note = "Use http:// only for local development"
        """)
        // This IS a string starting with "Use" not "http://" — should not flag
        #expect(issues.isEmpty)
    }

    @Test func testDoesNotFlagInterpolatedString() {
        let issues = issues(for: """
        let url = "http://\\(host)/api"
        """)
        // Interpolated strings are skipped (unsafeURL rule covers those)
        #expect(issues.isEmpty)
    }

    // MARK: - Helpers

    func issues(
        for source: String,
        filePath: String = "Sources/Networking/Client.swift"
    ) -> [LintIssue] {
        let sourceFile = Parser.parse(source: source)
        let visitor = InsecureTransportVisitor(patternCategory: .security)
        visitor.setFilePath(filePath)
        visitor.walk(sourceFile)
        return visitor.detectedIssues
    }
}
