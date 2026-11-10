@testable import Core
import Testing

@Suite
struct InsecureTransportVisitorTests {

    // MARK: - Flagged: plain http:// URLs

    @Test func testFlagsHTTPLiteral() {
        let issues = issues(for: """
        let endpoint = "http://api.myservice.com/v1/users"
        """)
        #expect(issues.count == 1)
    }

    @Test func testFlagsHTTPInURLInit() {
        let issues = issues(for: """
        let imageURL = URL(string: "http://cdn.example.org/photo.jpg")!
        """)
        // example.org is reserved — suppressed
        #expect(issues.isEmpty)
    }

    @Test func testFlagsHTTPWithPort() {
        let issues = issues(for: """
        let server = "http://staging.internal:9090/api"
        """)
        #expect(issues.count == 1)
    }

    @Test func testFlagsHTTPWithPath() {
        let issues = issues(for: """
        let url = "http://mycompany.com/images/logo.png"
        """)
        #expect(issues.count == 1)
    }

    @Test func testFlagsCaseInsensitive() {
        let issues = issues(for: """
        let url = "HTTP://MYAPI.COM/data"
        """)
        #expect(issues.count == 1)
    }

    @Test func testFlagsMultipleHTTPURLs() {
        let issues = issues(for: """
        let one = "http://api.one.com/v1"
        let two = "http://api.two.com/v2"
        let three = "https://secure.three.com/v3"
        """)
        #expect(issues.count == 2)
    }

    // MARK: - Suppressed: localhost

    @Test func testSuppressesLocalhost() {
        let issues = issues(for: """
        let devServer = "http://localhost:8080/api"
        """)
        #expect(issues.isEmpty)
    }

    @Test func testSuppressesLocalhostNoPort() {
        let issues = issues(for: """
        let devServer = "http://localhost/api"
        """)
        #expect(issues.isEmpty)
    }

    @Test func testSuppresses127001() {
        let issues = issues(for: """
        let devServer = "http://127.0.0.1:3000/health"
        """)
        #expect(issues.isEmpty)
    }

    @Test func testSuppressesIPv6Loopback() {
        let issues = issues(for: """
        let devServer = "http://[::1]:8080/api"
        """)
        #expect(issues.isEmpty)
    }

    // MARK: - Suppressed: reserved domains (RFC 2606)

    @Test func testSuppressesExampleCom() {
        let issues = issues(for: """
        let demo = "http://example.com/path"
        """)
        #expect(issues.isEmpty)
    }

    @Test func testSuppressesExampleOrg() {
        let issues = issues(for: """
        let demo = "http://example.org/docs"
        """)
        #expect(issues.isEmpty)
    }

    @Test func testSuppressesExampleNet() {
        let issues = issues(for: """
        let demo = "http://example.net/test"
        """)
        #expect(issues.isEmpty)
    }

    @Test func testSuppressesExampleEdu() {
        let issues = issues(for: """
        let demo = "http://example.edu/resource"
        """)
        #expect(issues.isEmpty)
    }

    // MARK: - Suppressed: test files

    @Test func testSuppressesTestFilePath() {
        let source = """
        let mockURL = "http://test-server.internal/mock"
        """
        let issues = issues(for: source, filePath: "Tests/NetworkTests/APITests.swift")
        #expect(issues.isEmpty)
    }

    @Test func testSuppressesXCTestFilePath() {
        let source = """
        let mockURL = "http://test-server.internal/mock"
        """
        let issues = issues(for: source, filePath: "XCTests/IntegrationTests/EndpointTests.swift")
        #expect(issues.isEmpty)
    }

    // MARK: - Suppressed: #if DEBUG

    @Test func testSuppressesInsideIfDebug() {
        let issues = issues(for: """
        #if DEBUG
        let devURL = "http://dev.myservice.com/api"
        #endif
        """)
        #expect(issues.isEmpty)
    }

    @Test func testFlagsOutsideIfDebug() {
        let issues = issues(for: """
        #if DEBUG
        let devURL = "http://dev.myservice.com/api"
        #endif
        let prodURL = "http://prod.myservice.com/api"
        """)
        #expect(issues.count == 1)
    }

    // MARK: - Flagged: ws:// WebSocket URLs

    @Test func testFlagsWSLiteral() {
        let issues = issues(for: """
        let socket = "ws://chat.myservice.com/connect"
        """)
        #expect(issues.count == 1)
    }

    @Test func testFlagsWSWithPort() {
        let issues = issues(for: """
        let socket = "ws://realtime.internal:8080/ws"
        """)
        #expect(issues.count == 1)
    }

    @Test func testFlagsWSCaseInsensitive() {
        let issues = issues(for: """
        let socket = "WS://CHAT.MYSERVICE.COM/connect"
        """)
        #expect(issues.count == 1)
    }

    @Test func testDoesNotFlagWSS() {
        let issues = issues(for: """
        let socket = "wss://chat.myservice.com/connect"
        """)
        #expect(issues.isEmpty)
    }

    // MARK: - Suppressed: ws:// localhost and reserved domains

    @Test func testSuppressesWSLocalhost() {
        let issues = issues(for: """
        let devSocket = "ws://localhost:8080/ws"
        """)
        #expect(issues.isEmpty)
    }

    @Test func testSuppressesWSExampleCom() {
        let issues = issues(for: """
        let demo = "ws://example.com/socket"
        """)
        #expect(issues.isEmpty)
    }

    @Test func testSuppressesWSInsideIfDebug() {
        let issues = issues(for: """
        #if DEBUG
        let devSocket = "ws://dev.myservice.com/ws"
        #endif
        """)
        #expect(issues.isEmpty)
    }

    @Test func testFlagsMixedHTTPAndWS() {
        let issues = issues(for: """
        let api = "http://api.myservice.com/v1"
        let socket = "ws://chat.myservice.com/ws"
        let secureAPI = "https://api.myservice.com/v1"
        let secureSocket = "wss://chat.myservice.com/ws"
        """)
        #expect(issues.count == 2)
    }
}
