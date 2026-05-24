//
//  ContentView.swift
//  FitnessLoadTracker
//

import BackgroundTasks
import SwiftUI
import UIKit

struct ContentView: View {
    @State private var manager = HealthKitManager()
    @State private var strava = StravaConnection()
    @State private var sync = SyncOrchestrator()
    @State private var bgPendingCount = 0
    @State private var bgNextDate: Date?

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                Text("FitnessLoadTracker")
                    .font(.title)

                stravaSection

                Divider()

                statusView

                bgStatus
            }
            .padding()
        }
        .task {
            await manager.requestAuthorization()
            // Re-arm so the readout reflects the latest submit attempt
            // (the App.init schedule runs in parallel and may not have
            // captured lastError by the time we render the first time).
            BackgroundSync.scheduleNext()
            await refreshBGStatus()
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

    // Debug-only readout so Tom can confirm BG refresh is registered without
    // waiting for an actual iOS-triggered fire. Removed once #5b lands the
    // persistent sync log that supersedes this.
    private var bgStatus: some View {
        let next = bgNextDate?.formatted(date: .omitted, time: .shortened) ?? "-"
        let refresh = refreshStatusLabel(UIApplication.shared.backgroundRefreshStatus)
        return VStack(alignment: .leading, spacing: 2) {
            Text("BG: pending=\(bgPendingCount), next=\(next)")
            Text("Refresh status: \(refresh)")
            if let err = BackgroundSync.lastError {
                Text("Submit error: \(err)")
                    .foregroundStyle(.red)
            }
        }
        .font(.caption.monospaced())
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func refreshStatusLabel(_ status: UIBackgroundRefreshStatus) -> String {
        switch status {
        case .available: return "available"
        case .denied:    return "denied (toggle Settings → General → Background App Refresh)"
        case .restricted: return "restricted (parental controls / MDM)"
        @unknown default: return "unknown"
        }
    }

    private func refreshBGStatus() async {
        let requests = await withCheckedContinuation { continuation in
            BGTaskScheduler.shared.getPendingTaskRequests { requests in
                continuation.resume(returning: requests)
            }
        }
        bgPendingCount = requests.count
        bgNextDate = requests.first?.earliestBeginDate
    }
}

#Preview {
    ContentView()
}
