import SwiftProjectLintModels
import SwiftProjectLintVisitors
import SwiftSyntax

/// Detects an `@ObservedObject` that the view's own initializer constructs.
///
/// `@ObservedObject` says the object belongs to someone else. A view struct is rebuilt every time its
/// parent's `body` runs, and its initializer runs again with it. An initializer that builds the
/// object therefore builds a new one on every parent update, and the old object's state is lost.
/// `@StateObject` keeps one object for the view's lifetime.
///
/// This is the initializer half of the mistake. `@ObservedObject var model = Model()`, the inline
/// half, is [ObservedObject Inline](observed-object-inline.md)'s, so a property with an inline
/// value is left to that rule and never reported twice.
///
/// What counts as constructing, in any initializer of the view:
/// - `self.model = Model(…)` or `model = Model(…)`, also `Model.init(…)` and `Model<T>(…)`;
/// - `_model = ObservedObject(wrappedValue: Model(…))`, or the older `initialValue:` label.
///
/// A capitalized callee is read as a type, so the check is syntactic. Assigning a parameter
/// (`self.model = model`), a shared instance (`Model.shared`) or a factory's result
/// (`makeModel()`) is not construction, and is not reported. Neither is
/// `init() { self.init(model: Model()) }`: the delegating call is not followed, which makes
/// the rule quieter rather than louder.
final class MissingStateObjectVisitor: BasePatternVisitor {

    required init(pattern: SyntaxPattern, viewMode: SyntaxTreeViewMode = .sourceAccurate) {
        super.init(pattern: pattern, viewMode: viewMode)
    }

    override func visit(_ node: StructDeclSyntax) -> SyntaxVisitorContinueKind {
        guard isSwiftUIView(node) else { return .visitChildren }

        let members = node.memberBlock.members
        let initializers = members.compactMap { $0.decl.as(InitializerDeclSyntax.self) }
        guard initializers.isEmpty == false else { return .visitChildren }

        for member in members {
            guard let variable = member.decl.as(VariableDeclSyntax.self), Self.isObservedObject(variable) else {
                continue
            }
            for binding in variable.bindings where binding.initializer == nil {
                guard let name = binding.pattern.as(IdentifierPatternSyntax.self)?.identifier.text,
                      initializers.contains(where: { Self.constructs(name, in: $0) }) else { continue }
                addIssue(
                    severity: .warning,
                    message: "'\(name)' is @ObservedObject, but \(node.name.text)'s initializer creates it: "
                        + "a new object is built, and its state lost, every time the parent updates the view",
                    filePath: getFilePath(for: Syntax(variable)),
                    lineNumber: getLineNumber(for: Syntax(variable)),
                    suggestion: "Declare it `@StateObject` and initialize it with "
                        + "`_\(name) = StateObject(wrappedValue: …)`, or pass the object in from the parent.",
                    ruleName: .missingStateObject
                )
            }
        }
        return .visitChildren
    }

    // MARK: - Helpers

    private static func isObservedObject(_ variable: VariableDeclSyntax) -> Bool {
        variable.attributes.contains { element in
            guard let attribute = element.as(AttributeSyntax.self) else { return false }
            let name = attribute.attributeName.as(IdentifierTypeSyntax.self)?.name.text
                ?? attribute.attributeName.as(MemberTypeSyntax.self)?.name.text
            return name == PropertyWrapper.observedObject.rawValue
        }
    }

    /// Whether `initializer` assigns `name` (or its storage `_name`) a newly constructed object.
    private static func constructs(_ name: String, in initializer: InitializerDeclSyntax) -> Bool {
        guard let body = initializer.body else { return false }
        return body.statements.contains { item in
            // The parser leaves `a = b` unfolded: a sequence of left side, `=` and right side.
            guard let sequence = item.item.as(SequenceExprSyntax.self) else { return false }
            let elements = Array(sequence.elements)
            guard elements.count == 3, elements[1].is(AssignmentExprSyntax.self),
                  let target = assignedName(elements[0]) else { return false }
            let value = elements[2]
            if target == name {
                return isConstruction(value)
            }
            if target == "_" + name, let wrapper = value.as(FunctionCallExprSyntax.self),
               calleeTypeName(wrapper) == PropertyWrapper.observedObject.rawValue {
                return wrapper.arguments.contains { argument in
                    let label = argument.label?.text
                    return (label == "wrappedValue" || label == "initialValue") && isConstruction(argument.expression)
                }
            }
            return false
        }
    }

    /// `x` for `x` and for `self.x`.
    private static func assignedName(_ expression: ExprSyntax) -> String? {
        if let reference = expression.as(DeclReferenceExprSyntax.self) {
            return reference.baseName.text
        }
        if let member = expression.as(MemberAccessExprSyntax.self),
           member.base?.as(DeclReferenceExprSyntax.self)?.baseName.tokenKind == .keyword(.self) {
            return member.declName.baseName.text
        }
        return nil
    }

    /// A call of a type: `Model(…)`, `Model.init(…)` or `Model<T>(…)`, but not `ObservedObject(…)`.
    private static func isConstruction(_ expression: ExprSyntax) -> Bool {
        guard let call = expression.as(FunctionCallExprSyntax.self), let type = calleeTypeName(call) else {
            return false
        }
        return type != PropertyWrapper.observedObject.rawValue
    }

    /// The capitalized type name a call constructs, or `nil` when the callee is not one.
    private static func calleeTypeName(_ call: FunctionCallExprSyntax) -> String? {
        var callee = call.calledExpression
        if let member = callee.as(MemberAccessExprSyntax.self), member.declName.baseName.tokenKind == .keyword(.`init`),
           let base = member.base {
            callee = base
        }
        if let specialized = callee.as(GenericSpecializationExprSyntax.self) {
            callee = specialized.expression
        }
        guard let name = callee.as(DeclReferenceExprSyntax.self)?.baseName.text,
              let first = name.first, first.isUppercase else { return nil }
        return name
    }
}
