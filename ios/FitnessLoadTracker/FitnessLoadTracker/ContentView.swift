//
//  ContentView.swift
//  FitnessLoadTracker
//

import SwiftUI

struct ContentView: View {
    @State private var manager = HealthKitManager()
    @State private var strava = StravaConnection()

    var body: some View {
        VStack(spacing: 24) {
            Text("FitnessLoadTracker")
                .font(.title)

            stravaSection

            Divider()

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
        .task {
            await manager.requestAuthorization()
        }
    }

    @ViewBuilder
    private var stravaSection: some View {
        switch strava.state {
        case .disconnected:
            Button {
                Task { await strava.connect() }
            } label: {
                Text("Connect to Strava")
                    .padding()
                    .frame(maxWidth: .infinity)
                    .background(Color.orange)
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            }
        case .connecting:
            ProgressView("Connecting…")
        case .connected(let name):
            VStack(spacing: 8) {
                Text("Connected as \(name)")
                    .foregroundStyle(.green)
                Button("Sync now (coming in #4b)") {}
                    .disabled(true)
            }
        case .failed(let message):
            VStack(spacing: 8) {
                Text(message)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
                Button("Try again") {
                    Task { await strava.connect() }
                }
            }
        }
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
