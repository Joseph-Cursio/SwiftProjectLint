import SwiftUI
import Combine

// swiftlint:disable all

// Animation Issue: Fat view demonstrating all 10 animation lint rules

struct AnimationIssuesExampleView: View {
    @State private var isVisible = false
    @State private var isExpanded = false
    @State private var scale: CGFloat = 1.0
    @State private var offset: CGFloat = 0
    @State private var count = 0
    let timer = Timer.publish(every: 0.1, on: .main, in: .common).autoconnect()

    // Rule: matchedGeometryEffectMisuse — @Namespace declared but used correctly below;
    // undeclared namespace used in a separate helper
    @Namespace private var heroNamespace

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {

                // Rule: defaultAnimationCurve — using .default curve
                Text("Default Curve")
                    .opacity(isVisible ? 1 : 0)
                    .animation(.default, value: isVisible)

                // Rule: conflictingAnimations — two .animation() modifiers on same value
                Text("Conflicting")
                    .scaleEffect(isExpanded ? 1.5 : 1.0)
                    .animation(.easeIn, value: isExpanded)
                    .animation(.spring(), value: isExpanded)

                // Rule: hardcodedAnimationValues — duration literal
                Text("Hardcoded Duration")
                    .offset(x: offset)
                    .animation(.easeIn(duration: 0.35), value: offset)

                // Rule: hardcodedAnimationValues — spring parameters
                Text("Hardcoded Spring")
                    .scaleEffect(scale)
                    .animation(.spring(response: 0.3, dampingFraction: 0.8), value: scale)

                // Rule: matchedGeometryEffectMisuse — undeclared namespace
                UndeclaredNamespaceHelper()

                // Rule: matchedGeometryEffectMisuse — duplicate ID in same namespace
                DuplicateIdHelper(ns: heroNamespace)

                // Rule: excessiveSpringAnimations (existing rule)
                ExcessiveSpringView()

                // Rule: longAnimationDuration (existing rule)
                Text("Slow Animation")
                    .opacity(isVisible ? 1 : 0)
                    .animation(.easeIn(duration: 3.5), value: isVisible)

                // Rule: animationInHighFrequencyUpdate (existing rule)
                Text("Count: \(count)")
                    .onReceive(timer) { _ in count += 1 }
                    .animation(.spring(), value: count)

                // Rule: deprecatedAnimation (existing rule)
                Text("Deprecated")
                    .animation(.easeIn)

                // Rule: missingWithAnimationBlock / implicitAnimation (existing rule)
                Button("Toggle") {
                    isVisible.toggle()
                }

            }
            .padding()
        }
        .navigationTitle("Animation Issues")
    }
}

// Helper for undeclared namespace misuse
private struct UndeclaredNamespaceHelper: View {
    var body: some View {
        // matchedGeometryEffectMisuse: 'undeclaredNS' is never declared with @Namespace
        Text("Hero Source")
            .matchedGeometryEffect(id: "hero", in: undeclaredNS)
    }

    // swiftlint:disable:next implicitly_unwrapped_optional
    var undeclaredNS: Namespace.ID { fatalError("undeclared") }
}

// Helper for duplicate ID misuse
private struct DuplicateIdHelper: View {
    let ns: Namespace.ID

    var body: some View {
        VStack {
            // matchedGeometryEffectMisuse: same id "card" used twice in same namespace
            RoundedRectangle(cornerRadius: 8)
                .matchedGeometryEffect(id: "card", in: ns)
                .frame(width: 80, height: 80)
            RoundedRectangle(cornerRadius: 8)
                .matchedGeometryEffect(id: "card", in: ns)
                .frame(width: 80, height: 80)
        }
    }
}

private struct ExcessiveSpringView: View {
    @State private var a = false
    @State private var b = false
    @State private var c = false
    @State private var d = false

    var body: some View {
        VStack {
            Text("Spring 1").animation(.spring(), value: a)
            Text("Spring 2").animation(.spring(), value: b)
            Text("Spring 3").animation(.spring(), value: c)
            Text("Spring 4").animation(.spring(), value: d)
        }
    }
}

// swiftlint:enable all

#Preview {
    NavigationStack {
        AnimationIssuesExampleView()
    }
}
