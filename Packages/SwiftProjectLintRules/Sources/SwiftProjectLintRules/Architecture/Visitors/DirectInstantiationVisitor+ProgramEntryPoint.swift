import Foundation
import SwiftProjectLintModels
import SwiftProjectLintVisitors
import SwiftSyntax

extension DirectInstantiationVisitor {
    // MARK: - Program entry point

    /// `main.swift` holds top-level code, which Swift permits in no other file: it *is* the
    /// program. Tracked by file name because there is no syntax to look at — the statements
    /// are simply at the top of the file.
    var isMainSwiftFile: Bool {
        PathString.lastComponent(of: currentFilePath) == "main.swift"
    }

    /// Protocols whose conformers the runtime constructs, leaving no initializer to inject
    /// through.
    ///
    /// `ArgumentParser` builds a command out of argv and calls `run()`. The synthesized
    /// initializer takes only the decoded `@Option`/`@Argument`/`@Flag` values, so there is no
    /// parameter for a dependency, and the one remaining spelling — a stored property with an
    /// inline default — is the shape this rule reports. Inside a command, every form of the
    /// fix the rule recommends is either impossible or itself a finding, which is the
    /// definition of advice with no reachable end state.
    private static let runtimeConstructedProtocols: Set<String> = [
        "ParsableCommand", "AsyncParsableCommand", "ParsableArguments"
    ]

    static func isRuntimeConstructed(_ inheritance: InheritanceClauseSyntax?) -> Bool {
        guard let inheritance else { return false }
        return inheritance.inheritedTypes.contains { inherited in
            guard let name = inherited.type.as(IdentifierTypeSyntax.self)?.name.text
            else { return false }
            return runtimeConstructedProtocols.contains(name)
        }
    }

    /// Whether a function declaration is the entry point of an entry type (see `isEntryType`).
    ///
    /// Both spellings. `static func main()` is the one `@main` calls, and a SwiftUI `App`\'s
    /// `init()` is where its `@State` containers are seeded — the Explorer target\'s file
    /// header describes exactly that as "its composition root injects the in-process SwiftLint
    /// backend instead of the subprocess one".
    func isEntryPointMember(named name: String, isStatic: Bool) -> Bool {
        guard entryTypeStack.last == true else { return false }
        return name == "main" && isStatic
    }

    /// Whether a member variable of an entry type runs on the runtime's own path into the
    /// program, rather than being code the program calls.
    ///
    /// Two kinds. An instance stored property's initializer runs as part of every initializer,
    /// and an entry type's `init()` is exempt — so `init() { store = CoreDataOrderStore() }` was
    /// silent while `private let store = CoreDataOrderStore()`, the same construction at the same
    /// moment, was reported. That is the Checkout sample app's `CheckoutApp`, and the way most
    /// small SwiftUI apps are wired: one service in a stored property, short of the three a
    /// composition root needs. And an `App`\'s `body` is read by the runtime; no caller could
    /// pass it anything, so a model built there from the stored service is the wiring itself.
    ///
    /// A `static` stored property is neither. No initializer fills it: it is a global every file
    /// can reach as `Server.store`, and building it in `main()` and passing it down is an
    /// injection. Any other computed property is ordinary code the app calls, like its methods.
    func isRuntimeDrivenMember(_ node: VariableDeclSyntax) -> Bool {
        guard entryTypeStack.last == true,
              node.parent?.is(MemberBlockItemSyntax.self) == true,
              !node.modifiers.contains(where: { modifier in
                  modifier.name.tokenKind == .keyword(.static) || modifier.name.tokenKind == .keyword(.class)
              })
        else { return false }
        return node.bindings.allSatisfy { binding in
            Self.isStored(binding) || Self.isBody(binding)
        }
    }

    /// Whether a binding has storage: no accessors, or only `willSet`/`didSet` observing it.
    private static func isStored(_ binding: PatternBindingSyntax) -> Bool {
        guard let accessors = binding.accessorBlock?.accessors else { return true }
        guard case .accessors(let list) = accessors else { return false }
        return list.allSatisfy { accessor in
            accessor.accessorSpecifier.tokenKind == .keyword(.willSet)
                || accessor.accessorSpecifier.tokenKind == .keyword(.didSet)
        }
    }

    private static func isBody(_ binding: PatternBindingSyntax) -> Bool {
        binding.pattern.as(IdentifierPatternSyntax.self)?.identifier.text == "body"
    }

    /// Whether a type is one the runtime constructs and enters: it carries `@main`, or it is a
    /// SwiftUI `App`.
    ///
    /// `App` without `@main` is the launcher spelling — an `@main enum` whose `main()` picks the
    /// real `App` or a bare one for a unit-test host. The `App` it picks is still built by
    /// `App.main()` through `init()`, so no caller reaches its initializer either. All fifteen
    /// `App`s in the sibling corpus carry `@main`; this is here because the reason is the same,
    /// not because a finding asked for it.
    static func isEntryType(_ attributes: AttributeListSyntax, _ inheritance: InheritanceClauseSyntax?) -> Bool {
        if carriesMainAttribute(attributes) { return true }
        guard let inheritance else { return false }
        return inheritance.inheritedTypes.contains { inherited in
            if let identifier = inherited.type.as(IdentifierTypeSyntax.self) {
                return identifier.name.text == "App"
            }
            if let member = inherited.type.as(MemberTypeSyntax.self) {
                return member.name.text == "App"
                    && member.baseType.as(IdentifierTypeSyntax.self)?.name.text == "SwiftUI"
            }
            return false
        }
    }
}
