//
//  ContentViewHeader.swift
//  SwiftProjectLint
//
//  Created by Joseph Cursio on 7/1/25.
//

import SwiftUI

/// The header section of the main content view.
///
/// This view displays the app icon, title, and description for the SwiftProjectLint application.
/// It provides a clean, modern design with proper accessibility support.
struct ContentViewHeader: View {
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "checkmark.shield")
                .font(.system(size: 60))
                .foregroundStyle(.blue)
                .accessibilityHidden(true)

            Text("Swift Project Linter")
                .font(.largeTitle)
                .fontWeight(.bold)
                .accessibilityLabel("Swift Project Linter")
                .accessibilityIdentifier("mainTitleLabel")

            Text("Detect cross-file issues and architectural problems")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .accessibilityLabel("Detect cross-file issues and architectural problems")
                .accessibilityIdentifier("mainDescriptionLabel")
        }
        .padding(.bottom, 20)
    }
}

#Preview {
    ContentViewHeader()
}
