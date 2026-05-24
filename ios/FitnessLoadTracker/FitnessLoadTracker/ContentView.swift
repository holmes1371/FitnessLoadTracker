//
//  ContentView.swift
//  FitnessLoadTracker
//

import SwiftUI

struct ContentView: View {
    @StateObject private var manager = HealthKitManager()

    var body: some View {
        VStack(spacing: 24) {
            Text("FitnessLoadTracker")
                .font(.title)

            Button {
                Task { await manager.setEffortSevenOnMostRecentWorkout() }
            } label: {
                Text("Set effort 7 on most recent workout")
                    .padding()
                    .frame(maxWidth: .infinity)
                    .background(Color.accentColor)
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            .disabled(manager.status == .working)

            statusView
        }
        .padding()
    }

    @ViewBuilder
    private var statusView: some View {
        switch manager.status {
        case .idle:
            Text("Tap the button to write effort 7 to your most recent workout.")
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        case .working:
            ProgressView()
        case .success(let message):
            Text(message)
                .foregroundStyle(.green)
                .multilineTextAlignment(.center)
        case .failure(let message):
            Text(message)
                .foregroundStyle(.red)
                .multilineTextAlignment(.center)
        }
    }
}

#Preview {
    ContentView()
}
