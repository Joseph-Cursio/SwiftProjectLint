import SwiftProjectLintVisitors
import SwiftSyntax

/// What a type's declaration says about where its members run.
enum TypeIsolation: Equatable {
    /// Isolated to the main actor, so the compiler puts every member there. The text says why.
    case mainActor(String)
    /// Not isolated, but an `@Observable` / `ObservableObject` model: SwiftUI calls its
    /// synchronous members from the main actor, so they run there anyway.
    case viewModel(String)
    /// Isolated somewhere else, or explicitly not isolated: an `actor`, another global actor,
    /// or `nonisolated`.
    case elsewhere
}

/// Every type the project declares, with what its declaration says about isolation.
///
/// Built from all files before any is scanned, so that `extension ContentView` in one file can
/// see that `ContentView: View` was declared in another, and `class DetailViewController:
/// BaseViewController` can find that `BaseViewController: UIViewController`.
struct MainActorTypeTable {

    /// SDK protocols that are `@MainActor`. A type that conforms to one in its own declaration
    /// is inferred `@MainActor` too.
    static let mainActorProtocols: Set<String> = [
        "View", "App", "Scene", "ViewModifier",
        "UIViewRepresentable", "UIViewControllerRepresentable",
        "NSViewRepresentable", "NSViewControllerRepresentable",
        "UIApplicationDelegate", "UISceneDelegate", "UIWindowSceneDelegate",
        "NSApplicationDelegate"
    ]

    /// SDK classes that are `@MainActor`. Every subclass inherits the isolation.
    static let mainActorClasses: Set<String> = [
        "UIResponder", "UIView", "UIControl", "UITableViewCell", "UICollectionViewCell",
        "UIViewController", "UITableViewController", "UICollectionViewController",
        "UINavigationController", "UITabBarController", "UIHostingController",
        "NSResponder", "NSView", "NSViewController", "NSWindow", "NSWindowController",
        "NSHostingController", "NSHostingView"
    ]

    /// One declaration's own evidence, before anything is inherited.
    struct Record {
        /// What the attributes and modifiers say: `@MainActor`, another global actor,
        /// `nonisolated`, or `actor`.
        var explicit: TypeIsolation?
        /// Superclass and conformances, by simple name.
        var inherited: [String]
        /// The declaration sits in a target compiled with default MainActor isolation.
        var defaultsToMainActor: Bool
        /// `@Observable` or `ObservableObject`, when the type is one.
        var modelKind: String?
        var isProtocol = false
    }

    private var records: [String: Record] = [:]

    /// The project's composition aliases. `struct ContentView: TestableView`, with
    /// `typealias TestableView = View & ViewInspectorHook`, conforms to `View`, and is
    /// `@MainActor` because of it. Read by name alone, the alias was neither a protocol nor a class
    /// the table knew, so nothing said where the view's members run.
    var compositionAliases = CompositionAliasCatalog.empty

    /// Records every type declared in `tree`.
    mutating func collect(from tree: SourceFileSyntax, defaultsToMainActor: Bool) {
        let collector = DeclarationCollector(viewMode: .sourceAccurate)
        collector.walk(tree)
        for (name, decl) in collector.declarations {
            let record = Self.record(for: decl, defaultsToMainActor: defaultsToMainActor)
            // Two types can share a simple name across modules; explicit evidence wins.
            if records[name]?.explicit == nil {
                records[name] = record
            }
        }
    }

    /// Where the members of `name`'s declaration run, or `nil` when nothing says.
    func isolation(of name: String) -> TypeIsolation? {
        if Self.mainActorProtocols.contains(name) || Self.mainActorClasses.contains(name) {
            return .mainActor("it extends \(name), which is @MainActor")
        }
        guard let record = records[name] else { return nil }
        return resolve(record, named: name, visiting: [])
    }

    /// Whether conforming to `name` makes a type `@MainActor`: an SDK protocol that is, or a
    /// project protocol that says so.
    func isMainActorProtocol(_ name: String) -> Bool {
        if Self.mainActorProtocols.contains(name) {
            return true
        }
        guard let record = records[name], record.isProtocol, case .mainActor = record.explicit else {
            return false
        }
        return true
    }

    /// Where the members of a declaration with `record` run, or `nil` when nothing says.
    func resolve(_ record: Record, named name: String, visiting: Set<String>) -> TypeIsolation? {
        if let explicit = record.explicit {
            return explicit
        }
        if let inherited = inheritedMainActor(record.inherited, named: name, visiting: visiting) {
            return inherited
        }
        if record.defaultsToMainActor {
            return .mainActor("'\(name)' is in a target that defaults to MainActor isolation")
        }
        return record.modelKind.map {
            .viewModel("'\(name)' is an \($0) model, and SwiftUI calls its synchronous members "
                + "on the main actor")
        }
    }

    private func inheritedMainActor(
        _ inherited: [String],
        named name: String,
        visiting: Set<String>
    ) -> TypeIsolation? {
        for parent in inherited.flatMap(compositionAliases.expand) {
            if Self.mainActorProtocols.contains(parent) {
                return .mainActor("'\(name)' conforms to \(parent), which is @MainActor")
            }
            if Self.mainActorClasses.contains(parent) {
                return .mainActor("'\(name)' inherits @MainActor from \(parent)")
            }
            guard visiting.contains(parent) == false, let parentRecord = records[parent] else { continue }
            if parentRecord.isProtocol {
                // Conformance passes on only the isolation the protocol spells out.
                if case .mainActor = parentRecord.explicit {
                    return .mainActor("'\(name)' conforms to '\(parent)', which is @MainActor")
                }
                continue
            }
            // A superclass passes on the isolation the compiler gives it; a model's role does not.
            let parentIsolation = resolve(parentRecord, named: parent, visiting: visiting.union([name]))
            if case .mainActor = parentIsolation {
                return .mainActor("'\(name)' inherits @MainActor from '\(parent)'")
            }
        }
        return nil
    }

    // MARK: - Reading a declaration

    static func record(for decl: some DeclGroupSyntax, defaultsToMainActor: Bool) -> Record {
        let inherited = inheritedNames(decl.inheritanceClause)
        let isObservable = hasAttribute(decl.attributes, named: "Observable")
        return Record(
            explicit: explicitIsolation(of: decl, name: declName(decl)),
            inherited: inherited,
            defaultsToMainActor: defaultsToMainActor,
            modelKind: isObservable ? "@Observable"
                : inherited.contains("ObservableObject") ? "ObservableObject" : nil,
            isProtocol: decl.is(ProtocolDeclSyntax.self)
        )
    }

    private static func explicitIsolation(of decl: some DeclGroupSyntax, name: String) -> TypeIsolation? {
        if decl.is(ActorDeclSyntax.self) {
            return .elsewhere
        }
        return explicitIsolation(attributes: decl.attributes, modifiers: decl.modifiers, subject: "'\(name)'")
    }

    /// What `@MainActor`, another global actor, `@concurrent` or `nonisolated` on a declaration
    /// says, with `subject` naming it in the reason.
    static func explicitIsolation(
        attributes: AttributeListSyntax,
        modifiers: DeclModifierListSyntax,
        subject: String
    ) -> TypeIsolation? {
        if hasAttribute(attributes, named: "MainActor") {
            return .mainActor("\(subject) is @MainActor")
        }
        if modifiers.contains(where: { $0.name.tokenKind == .keyword(.nonisolated) })
            || hasAttribute(attributes, named: "concurrent")
            || attributeNames(attributes).contains(where: { $0.hasSuffix("Actor") }) {
            return .elsewhere
        }
        return nil
    }

    static func hasAttribute(_ attributes: AttributeListSyntax, named name: String) -> Bool {
        attributeNames(attributes).contains(name)
    }

    private static func attributeNames(_ attributes: AttributeListSyntax) -> [String] {
        attributes.compactMap { element in
            element.as(AttributeSyntax.self).map { simpleName($0.attributeName) }
        }
    }

    static func inheritedNames(_ clause: InheritanceClauseSyntax?) -> [String] {
        clause?.inheritedTypes.map { simpleName($0.type) } ?? []
    }

    /// `View` for `View`, `SwiftUI.View` and `UIHostingController<Root>` alike.
    static func simpleName(_ type: TypeSyntax) -> String {
        if let identifier = type.as(IdentifierTypeSyntax.self) {
            return identifier.name.text
        }
        if let member = type.as(MemberTypeSyntax.self) {
            return member.name.text
        }
        return type.trimmedDescription
    }

    static func declName(_ decl: some DeclGroupSyntax) -> String {
        if let named = decl.asProtocol(NamedDeclSyntax.self) {
            return named.name.text
        }
        return decl.as(ExtensionDeclSyntax.self).map { simpleName($0.extendedType) } ?? ""
    }
}

/// Every class, struct, enum, actor and protocol in a file, nested ones included.
private final class DeclarationCollector: SyntaxVisitor {
    private(set) var declarations: [(String, any DeclGroupSyntax)] = []

    override func visit(_ node: ClassDeclSyntax) -> SyntaxVisitorContinueKind {
        declarations.append((node.name.text, node))
        return .visitChildren
    }

    override func visit(_ node: StructDeclSyntax) -> SyntaxVisitorContinueKind {
        declarations.append((node.name.text, node))
        return .visitChildren
    }

    override func visit(_ node: EnumDeclSyntax) -> SyntaxVisitorContinueKind {
        declarations.append((node.name.text, node))
        return .visitChildren
    }

    override func visit(_ node: ActorDeclSyntax) -> SyntaxVisitorContinueKind {
        declarations.append((node.name.text, node))
        return .visitChildren
    }

    override func visit(_ node: ProtocolDeclSyntax) -> SyntaxVisitorContinueKind {
        declarations.append((node.name.text, node))
        return .skipChildren
    }

    // Function bodies can't declare types this table needs.
    override func visit(_: FunctionDeclSyntax) -> SyntaxVisitorContinueKind { .skipChildren }
}
