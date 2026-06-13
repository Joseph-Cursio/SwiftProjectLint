@testable import Core
import SwiftParser
@testable import SwiftProjectLintRules
import SwiftSyntax
import Testing

@Suite
struct SwallowedInjectionDowncastVisitorTests {

    private func analyze(_ source: String) -> [LintIssue] {
        let visitor = SwallowedInjectionDowncastVisitor(pattern: SwallowedInjectionDowncast().pattern)
        visitor.walk(Parser.parse(source: source))
        return visitor.detectedIssues.filter { $0.ruleName == .swallowedInjectionDowncast }
    }

    /// The exact bug this rule was born from (SwiftLintCLIActor's cache injection).
    @Test func flagsTheOriginalBugShape() throws {
        let source = """
        actor Service {
            let cache: CacheManager
            init(cache: CacheManagerProtocol? = nil) {
                if let provided = cache as? CacheManager {
                    self.cache = provided
                } else {
                    self.cache = CacheManager()
                }
            }
        }
        """
        let issues = analyze(source)
        #expect(issues.count == 1)
        let issue = try #require(issues.first)
        #expect(issue.severity == .info)
        #expect(issue.message.contains("cache"))
        #expect(issue.message.contains("CacheManager"))
    }

    @Test func flagsAnyExistentialParameterDowncast() {
        let source = """
        struct Wrapper {
            init(service: any Networking) {
                self.client = service as? URLSessionClient
            }
        }
        """
        #expect(analyze(source).count == 1)
    }

    @Test func flagsForcedDowncast() {
        let source = """
        struct Wrapper {
            init(store: StoreProtocol) {
                self.concrete = store as! DiskStore
            }
        }
        """
        #expect(analyze(source).count == 1)
    }

    // MARK: - Negatives

    @Test func ignoresDowncastToAnotherProtocol() {
        // Narrowing one protocol to another is legitimate, not a swallowed injection.
        let source = """
        struct Wrapper {
            init(service: ServiceProtocol) {
                self.extra = service as? ExtraCapabilityProtocol
            }
        }
        """
        #expect(analyze(source).isEmpty)
    }

    @Test func ignoresConcreteParameter() {
        // A concrete parameter being downcast is a different (non-injection) concern.
        let source = """
        struct Wrapper {
            init(value: NSObject) {
                self.view = value as? NSView
            }
        }
        """
        #expect(analyze(source).isEmpty)
    }

    @Test func ignoresDowncastOutsideInitializer() {
        let source = """
        struct Wrapper {
            func configure(service: ServiceProtocol) {
                self.concrete = service as? ConcreteService
            }
        }
        """
        #expect(analyze(source).isEmpty)
    }

    @Test func ignoresInitWithNoDowncast() {
        let source = """
        struct Wrapper {
            let service: any ServiceProtocol
            init(service: any ServiceProtocol) {
                self.service = service
            }
        }
        """
        #expect(analyze(source).isEmpty)
    }
}
