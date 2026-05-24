//
//  ContentView.swift
//  FitnessLoadTracker
//

import SwiftUI

struct ContentView: View {
    @State private var manager = HealthKitManager()
    @State private var strava = StravaConnection()
    @State private var sync = SyncOrchestrator()

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                Text("FitnessLoadTracker")
                    .font(.title)

                stravaSection

                Divider()

                debugButton

                statusView
            }
            .padding()
        }
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
            VStack(spacing: 12) {
                Text("Connected as \(name)")
                    .foregroundStyle(.green)
                Button {
                    Task { await sync.syncRecentActivities(healthKit: manager) }
                } label: {
                    Text(sync.isSyncing ? "Syncing…" : "Sync now")
                        .padding()
                        .frame(maxWidth: .infinity)
                        .background(Color.blue)
                        .foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                .disabled(sync.isSyncing)

                syncResults
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
    private var syncResults: some View {
        if let error = sync.errorMessage {
            Text(error)
                .foregroundStyle(.red)
                .multilineTextAlignment(.center)
        }
        if !sync.items.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                ForEach(sync.items) { item in
                    HStack {
                        VStack(alignment: .leading) {
                            Text(item.activity.name)
                                .font(.subheadline)
                            Text(item.activity.startDate.formatted(date: .abbreviated, time: .shortened))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        statusLabel(for: item.status)
                    }
                    Divider()
                }
            }
        }
    }

    @ViewBuilder
    private func statusLabel(for status: SyncOrchestrator.ItemStatus) -> some View {
        switch status {
        case .pending:
            Text("…").foregroundStyle(.secondary)
        case .written(let effort):
            Text("Effort \(effort, specifier: "%.0f")").foregroundStyle(.green)
        case .skippedNoSufferScore:
            Text("No score").foregroundStyle(.secondary)
        case .skippedNoMatch:
            Text("No match").foregroundStyle(.secondary)
        case .skippedMultipleMatches:
            Text("Multiple matches").foregroundStyle(.orange)
        case .skippedAlreadyHasEffort:
            Text("Already has effort").foregroundStyle(.secondary)
        case .error(let msg):
            Text(msg).foregroundStyle(.red).font(.caption)
        }
    }

    private var debugButton: some View {
        Button {
            Task { await manager.setEffortSevenOnMostRecentWorkout() }
        } label: {
            Text("Set effort 7 on most recent workout")
                .padding()
                .frame(maxWidth: .infinity)
                .background(Color.gray.opacity(0.4))
                .foregroundStyle(.white)
                .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .disabled(manager.status == .working)
    }

    @ViewBuilder
    private var statusView: some View {
        switch manager.status {
        case .idle:
            EmptyView()
        case .working:
            ProgressView()
        case .success(let message):
            Text(message)
                .foregroundStyle(.green)
                .multilineTextAlignment(.center)
                .font(.caption)
        case .failure(let message):
            Text(message)
                .foregroundStyle(.red)
                .multilineTextAlignment(.center)
                .font(.caption)
        }
    }
}

#Preview {
    ContentView()
}
