import Testing
@testable import Core
@testable import SwiftProjectLintRules
import SwiftSyntax
import SwiftParser

@Suite
struct StringSwitchOverEnumVisitorTests {

    private func makeVisitor() -> StringSwitchOverEnumVisitor {
        let pattern = StringSwitchOverEnum().pattern
        return StringSwitchOverEnumVisitor(pattern: pattern)
    }

    private func runVisitor(_ visitor: StringSwitchOverEnumVisitor, source: String) {
        let sourceFile = Parser.parse(source: source)
        visitor.walk(sourceFile)
    }

    // MARK: - Flagged: .rawValue Switch

    @Test
    func detectsRawValueSwitchWithStringLiterals() throws {
        let source = """
        let status = Status.active
        switch status.rawValue {
        case "active": handleActive()
        case "inactive": handleInactive()
        default: break
        }
        """
        let visitor = makeVisitor()
        runVisitor(visitor, source: source)

        #expect(visitor.detectedIssues.count == 1)

        let issue = try #require(visitor.detectedIssues.first)
        #expect(issue.ruleName == .stringSwitchOverEnum)
        #expect(issue.severity == .info)
        #expect(issue.message.contains(".rawValue"))
    }

    @Test("Detects .rawValue on a property chain")
    func detectsRawValueOnPropertyChain() {
        let source = """
        switch user.role.rawValue {
        case "admin": grantAccess()
        case "viewer": limitAccess()
        default: denyAccess()
        }
        """
        let visitor = makeVisitor()
        runVisitor(visitor, source: source)
        #expect(visitor.detectedIssues.count == 1)
    }

    @Test("Detects .rawValue with multiple string cases")
    func detectsMultipleStringCases() {
        let source = """
        switch priority.rawValue {
        case "high": escalate()
        case "medium": queue()
        case "low": defer()
        default: break
        }
        """
        let visitor = makeVisitor()
        runVisitor(visitor, source: source)
        #expect(visitor.detectedIssues.count == 1)
    }

    // MARK: - Flagged: String(describing:)

    @Test("Detects String(describing:) switch")
    func detectsStringDescribing() {
        let source = """
        switch String(describing: status) {
        case "active": handleActive()
        case "inactive": handleInactive()
        default: break
        }
        """
        let visitor = makeVisitor()
        runVisitor(visitor, source: source)
        #expect(visitor.detectedIssues.count == 1)
    }

    // MARK: - Not Flagged: Direct Enum Switch

    @Test("No issue when switching on enum directly")
    func noIssueForDirectEnumSwitch() {
        let source = """
        switch status {
        case .active: handleActive()
        case .inactive: handleInactive()
        case .pending: handlePending()
        }
        """
        let visitor = makeVisitor()
        runVisitor(visitor, source: source)
        #expect(visitor.detectedIssues.isEmpty)
    }

    // MARK: - Not Flagged: Non-String Cases

    @Test("No issue when .rawValue cases are not string literals")
    func noIssueForNonStringCases() {
        let source = """
        switch code.rawValue {
        case 0: handleZero()
        case 1: handleOne()
        default: break
        }
        """
        let visitor = makeVisitor()
        runVisitor(visitor, source: source)
        #expect(visitor.detectedIssues.isEmpty)
    }

    // MARK: - Not Flagged: Non-.rawValue Member Access

    @Test("No issue for switching on other member properties")
    func noIssueForNonRawValueMember() {
        let source = """
        switch item.name {
        case "foo": handleFoo()
        case "bar": handleBar()
        default: break
        }
        """
        let visitor = makeVisitor()
        runVisitor(visitor, source: source)
        #expect(visitor.detectedIssues.isEmpty)
    }

    // MARK: - Not Flagged: Plain String Variable

    @Test("No issue for switching on a plain string variable")
    func noIssueForPlainStringSwitch() {
        let source = """
        let text = "hello"
        switch text {
        case "hello": greet()
        case "bye": farewell()
        default: break
        }
        """
        let visitor = makeVisitor()
        runVisitor(visitor, source: source)
        #expect(visitor.detectedIssues.isEmpty)
    }

    // MARK: - Suppression: Codable init(from:)

    @Test("Suppressed inside Codable init(from decoder:)")
    func suppressedInCodableInit() {
        let source = """
        struct MyType: Codable {
            let status: Status

            init(from decoder: Decoder) throws {
                let container = try decoder.container(keyedBy: CodingKeys.self)
                let raw = try container.decode(String.self, forKey: .status)
                switch raw.rawValue {
                case "active": self.status = .active
                case "inactive": self.status = .inactive
                default: self.status = .unknown
                }
            }
        }
        """
        let visitor = makeVisitor()
        runVisitor(visitor, source: source)
        #expect(visitor.detectedIssues.isEmpty)
    }

    @Test("Suppressed inside encode(to encoder:)")
    func suppressedInEncodeMethod() {
        let source = """
        struct MyType: Codable {
            let status: Status

            func encode(to encoder: Encoder) throws {
                switch status.rawValue {
                case "active": try encodeActive(encoder)
                default: try encodeDefault(encoder)
                }
            }
        }
        """
        let visitor = makeVisitor()
        runVisitor(visitor, source: source)
        #expect(visitor.detectedIssues.isEmpty)
    }

    // MARK: - Not Suppressed: Regular Method

    @Test("Not suppressed in a regular method")
    func notSuppressedInRegularMethod() {
        let source = """
        struct Handler {
            func process() {
                switch status.rawValue {
                case "active": handleActive()
                default: break
                }
            }
        }
        """
        let visitor = makeVisitor()
        runVisitor(visitor, source: source)
        #expect(visitor.detectedIssues.count == 1)
    }

    // MARK: - Multiple Switches

    @Test("Detects multiple offending switches in same source")
    func detectsMultipleSwitches() {
        let source = """
        switch status.rawValue {
        case "a": doA()
        default: break
        }
        switch priority.rawValue {
        case "high": escalate()
        default: break
        }
        """
        let visitor = makeVisitor()
        runVisitor(visitor, source: source)
        #expect(visitor.detectedIssues.count == 2)
    }
}
