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
    @State private var recentSyncs: [SyncLogEntry] = []
    @State private var debugActivityID: String = ""

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                Text("FitnessLoadTracker")
                    .font(.title)

                stravaSection

                Divider()

                statusView

                recentSyncsSection

                bgStatus
            }
            .padding()
        }
        .task {
            await manager.requestAuthorization()
            await FailureNotifier.requestAuthorization()
            // Re-arm so the readout reflects the latest submit attempt
            // (the App.init schedule runs in parallel and may not have
            // captured lastError by the time we render the first time).
            BackgroundSync.scheduleNext()
            await refreshBGStatus()
            recentSyncs = SyncLog.recent()
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
                    Task {
                        await sync.syncRecentActivities(source: .foreground, healthKit: manager)
                        recentSyncs = SyncLog.recent()
                        await refreshBGStatus()
                    }
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

                debugSingleActivitySection
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
    private var debugSingleActivitySection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Debug: sync single activity")
                .font(.caption.bold())
                .foregroundStyle(.secondary)
            HStack {
                TextField("Strava activity ID", text: $debugActivityID)
                    .textFieldStyle(.roundedBorder)
                    .keyboardType(.numberPad)
                    .autocorrectionDisabled()
                Button("Sync") {
                    guard let id = Int64(debugActivityID) else { return }
                    Task {
                        await sync.syncSingleActivity(id: id, source: .foreground, healthKit: manager)
                        recentSyncs = SyncLog.recent()
                    }
                }
                .disabled(Int64(debugActivityID) == nil || sync.isSyncing)
            }

            // One-time backfill from 2024-10-10. Removed once the
            // history is in HK; no longer needed under normal sync.
            Button("Backfill from 2024-10-10") {
                Task {
                    var components = DateComponents()
                    components.year = 2024
                    components.month = 10
                    components.day = 10
                    let after = Calendar(identifier: .gregorian).date(from: components)!
                    await sync.syncBackfill(after: after, source: .foreground, healthKit: manager)
                    recentSyncs = SyncLog.recent()
                }
            }
            .font(.caption)
            .disabled(sync.isSyncing)
        }
        .padding(.top, 8)
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
        case .writtenAsNew(let effort):
            Text("Created + Effort \(effort, specifier: "%.0f")").foregroundStyle(.green)
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

    @ViewBuilder
    private var recentSyncsSection: some View {
        if !recentSyncs.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text("Recent syncs")
                    .font(.headline)
                ForEach(recentSyncs) { entry in
                    HStack(spacing: 8) {
                        sourcePill(for: entry.source)
                        Text(entry.timestamp.formatted(date: .abbreviated, time: .shortened))
                            .font(.caption)
                        Spacer()
                        Text("\(entry.activitiesProcessed) activities")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        if entry.perItemErrors > 0 || entry.errorSummary != nil {
                            Text("⚠")
                                .foregroundStyle(.orange)
                        }
                    }
                    Divider()
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func sourcePill(for source: SyncLogEntry.Source) -> some View {
        let (label, color): (String, Color) = source == .foreground
            ? ("FG", .blue)
            : ("BG", .purple)
        return Text(label)
            .font(.caption2.bold())
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(color)
            .foregroundStyle(.white)
            .clipShape(Capsule())
    }

    // Live BG state — pending request count, next earliest fire time, system
    // BG refresh permission, last submit error. Complementary to the
    // historical view in Recent syncs.
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
