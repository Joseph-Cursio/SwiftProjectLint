//
//  ContentViewProgress.swift
//  SwiftProjectLint
//
//  Created by Joseph Cursio on 7/1/25.
//

import SwiftUI

/// The progress indicator section of the main content view.
///
/// This view displays a progress indicator and status message when analysis is in progress.
/// It's only shown when the `isAnalyzing` state is true.
struct ContentViewProgress: View {
    let isAnalyzing: Bool

    var body: some View {
        if isAnalyzing {
            VStack(spacing: 8) {
                ProgressView()
                    .scaleEffect(1.2)
                Text("Analyzing project...")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, 20)
        }
    }
}

#Preview {
    VStack {
        ContentViewProgress(isAnalyzing: false)
        Divider()
        ContentViewProgress(isAnalyzing: true)
    }
    .padding()
}
