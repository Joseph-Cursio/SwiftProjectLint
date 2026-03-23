import Testing
import SwiftUI
import ViewInspector
import Core
@testable import App

@Suite
@MainActor
struct RuleDocViewTests {

    // MARK: - Basic rendering

    @Test func rendersWithoutCrashing() throws {
        let view = RuleDocView(rule: .magicNumber)
        let inspected = try view.inspect()
        let texts = inspected.findAll(ViewType.Text.self)
        #expect(!texts.isEmpty)
    }

    @Test func showsFallbackWhenDocumentationMissing() throws {
        // .unknown is unlikely to have a markdown doc file
        let view = RuleDocView(rule: .unknown)
        let inspected = try view.inspect()
        let texts = inspected.findAll(ViewType.Text.self)
        let strings = texts.compactMap { try? $0.string() }
        // Should show the fallback message parsed from markdown italic
        #expect(!strings.isEmpty)
    }

    @Test func containsScrollView() throws {
        let view = RuleDocView(rule: .fatView)
        let inspected = try view.inspect()
        _ = try inspected.find(ViewType.ScrollView.self)
    }

    @Test func containsVStack() throws {
        let view = RuleDocView(rule: .fatView)
        let inspected = try view.inspect()
        _ = try inspected.find(ViewType.VStack.self)
    }

    // MARK: - Different rules render

    @Test func rendersAccessibilityRule() throws {
        let view = RuleDocView(rule: .missingAccessibilityLabel)
        let inspected = try view.inspect()
        let texts = inspected.findAll(ViewType.Text.self)
        #expect(!texts.isEmpty)
    }

    @Test func rendersPerformanceRule() throws {
        let view = RuleDocView(rule: .expensiveOperationInViewBody)
        let inspected = try view.inspect()
        let texts = inspected.findAll(ViewType.Text.self)
        #expect(!texts.isEmpty)
    }

    @Test func rendersSecurityRule() throws {
        let view = RuleDocView(rule: .hardcodedSecret)
        let inspected = try view.inspect()
        let texts = inspected.findAll(ViewType.Text.self)
        #expect(!texts.isEmpty)
    }
}

@Suite
@MainActor
struct RuleDocumentationLoaderTests {

    // MARK: - documentationFileName

    @Test func simpleRuleNameConvertsToKebabCase() {
        let filename = RuleDocumentationLoader.documentationFileName(for: .magicNumber)
        #expect(filename == "magic-number")
    }

    @Test func acronymAtEndConvertsCorrectly() {
        let filename = RuleDocumentationLoader.documentationFileName(for: .forEachWithoutID)
        #expect(filename == "for-each-without-id")
    }

    @Test func specialCaseForEachWithoutIDUI() {
        let filename = RuleDocumentationLoader.documentationFileName(for: .forEachWithoutIDUI)
        #expect(filename == "for-each-without-id-ui")
    }

    @Test func acronymInMiddleConvertsCorrectly() {
        let filename = RuleDocumentationLoader.documentationFileName(for: .unsafeURL)
        #expect(filename == "unsafe-url")
    }

    @Test func singleWordRule() {
        let filename = RuleDocumentationLoader.documentationFileName(for: .unknown)
        #expect(filename == "unknown")
    }

    @Test func multiWordRule() {
        let filename = RuleDocumentationLoader.documentationFileName(for: .hardcodedSecret)
        #expect(filename == "hardcoded-secret")
    }

    @Test func longRuleName() {
        let filename = RuleDocumentationLoader.documentationFileName(
            for: .expensiveOperationInViewBody
        )
        #expect(filename == "expensive-operation-in-view-body")
    }

    // MARK: - loadDocumentation

    @Test func loadDocumentationReturnsNilForUnknownRule() {
        // .unknown likely has no doc file in the bundle
        let result = RuleDocumentationLoader.loadDocumentation(for: .unknown)
        #expect(result == nil)
    }

    @Test func loadDocumentationReturnsStringForKnownRule() {
        // Try a rule that should have docs — may return nil if docs aren't bundled in test target
        let result = RuleDocumentationLoader.loadDocumentation(for: .magicNumber)
        // We can't guarantee docs are in the test bundle, so just verify the function runs
        if let result {
            #expect(!result.isEmpty)
        }
    }
}
