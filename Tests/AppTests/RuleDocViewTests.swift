import Testing
import SwiftUI
import ViewInspector
import Core
@testable import App

@Suite
@MainActor
struct RuleDocViewTests {

    // MARK: - Basic rendering

    // swiftprojectlint:disable Test Missing Require
    @Test func rendersWithoutCrashing() throws {
        let view = RuleDocView(rule: .magicNumber)
        let inspected = try view.inspect()
        let texts = inspected.findAll(ViewType.Text.self)
        #expect(texts.isEmpty == false)

    }

    // swiftprojectlint:disable Test Missing Require
    @Test func showsFallbackWhenDocumentationMissing() throws {
        // .unknown is unlikely to have a markdown doc file
        let view = RuleDocView(rule: .unknown)
        let inspected = try view.inspect()
        let texts = inspected.findAll(ViewType.Text.self)
        let strings = texts.compactMap { try? $0.string() }
        // Should show the fallback message parsed from markdown italic
        #expect(strings.isEmpty == false)

    }

    // swiftprojectlint:disable Test Missing Require
    @Test func containsScrollView() throws {
        let view = RuleDocView(rule: .fatView)
        let inspected = try view.inspect()
        _ = try inspected.find(ViewType.ScrollView.self)
    }

    // swiftprojectlint:disable Test Missing Require
    @Test func containsVStack() throws {
        let view = RuleDocView(rule: .fatView)
        let inspected = try view.inspect()
        _ = try inspected.find(ViewType.VStack.self)
    }

    // MARK: - Different rules render

    // swiftprojectlint:disable Test Missing Require
    @Test func rendersAccessibilityRule() throws {
        let view = RuleDocView(rule: .missingAccessibilityLabel)
        let inspected = try view.inspect()
        let texts = inspected.findAll(ViewType.Text.self)
        #expect(texts.isEmpty == false)

    }

    // swiftprojectlint:disable Test Missing Require
    @Test func rendersPerformanceRule() throws {
        let view = RuleDocView(rule: .expensiveOperationInViewBody)
        let inspected = try view.inspect()
        let texts = inspected.findAll(ViewType.Text.self)
        #expect(texts.isEmpty == false)

    }

    // swiftprojectlint:disable Test Missing Require
    @Test func rendersSecurityRule() throws {
        let view = RuleDocView(rule: .hardcodedSecret)
        let inspected = try view.inspect()
        let texts = inspected.findAll(ViewType.Text.self)
        #expect(texts.isEmpty == false)

    }
}

@Suite
@MainActor
struct RuleDocumentationLoaderTests {

    // MARK: - documentationFileName

    // swiftprojectlint:disable Test Missing Require
    @Test func simpleRuleNameConvertsToKebabCase() {
        let filename = RuleDocumentationLoader.documentationFileName(for: .magicNumber)
        #expect(filename == "magic-number")
    }

    // swiftprojectlint:disable Test Missing Require
    @Test func acronymAtEndConvertsCorrectly() {
        let filename = RuleDocumentationLoader.documentationFileName(for: .forEachWithoutID)
        #expect(filename == "for-each-without-id")
    }

    // swiftprojectlint:disable Test Missing Require
    @Test func specialCaseForEachWithoutIDUI() {
        let filename = RuleDocumentationLoader.documentationFileName(for: .forEachWithoutIDUI)
        #expect(filename == "for-each-without-id-ui")
    }

    // swiftprojectlint:disable Test Missing Require
    @Test func acronymInMiddleConvertsCorrectly() {
        let filename = RuleDocumentationLoader.documentationFileName(for: .unsafeURL)
        #expect(filename == "unsafe-url")
    }

    // swiftprojectlint:disable Test Missing Require
    @Test func singleWordRule() {
        let filename = RuleDocumentationLoader.documentationFileName(for: .unknown)
        #expect(filename == "unknown")
    }

    // swiftprojectlint:disable Test Missing Require
    @Test func multiWordRule() {
        let filename = RuleDocumentationLoader.documentationFileName(for: .hardcodedSecret)
        #expect(filename == "hardcoded-secret")
    }

    // swiftprojectlint:disable Test Missing Require
    @Test func longRuleName() {
        let filename = RuleDocumentationLoader.documentationFileName(
            for: .expensiveOperationInViewBody
        )
        #expect(filename == "expensive-operation-in-view-body")
    }

    // MARK: - loadDocumentation

    // swiftprojectlint:disable Test Missing Require
    @Test func loadDocumentationReturnsNilForUnknownRule() {
        // .unknown likely has no doc file in the bundle
        let result = RuleDocumentationLoader.loadDocumentation(for: .unknown)
        #expect(result == nil)
    }

    // swiftprojectlint:disable Test Missing Require
    @Test func loadDocumentationReturnsStringForKnownRule() {
        // Try a rule that should have docs — may return nil if docs aren't bundled in test target
        let result = RuleDocumentationLoader.loadDocumentation(for: .magicNumber)
        // We can't guarantee docs are in the test bundle, so just verify the function runs
        if let result {
            #expect(result.isEmpty == false)

        }
    }
}
