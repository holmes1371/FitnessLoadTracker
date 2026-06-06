//
//  ContentView.swift
//  FitnessLoadTracker
//

import BackgroundTasks
import HealthKit
import SwiftUI
import UIKit

struct ContentView: View {
    @State private var manager = HealthKitManager()
    @State private var strava = StravaConnection()
    @State private var sync = SyncOrchestrator()
    @State private var bgPendingCount = 0
    @State private var bgNextDate: Date?
    @State private var recentSyncs: [SyncLogEntry] = []
    @State private var expandedSyncIDs: Set<UUID> = []
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

                duplicatesSection

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
        }
        .padding(.top, 8)
    }

    // Filter out `.skippedAlreadyHasEffort` — with the 24h overlap (#24),
    // a routine Sync re-fetches recent activities and stamps them all
    // "already has effort". That's pure noise; the Recent syncs section
    // still shows the full processed count for audit.
    private var displayItems: [SyncOrchestrator.Item] {
        sync.items.filter {
            if case .skippedAlreadyHasEffort = $0.status { return false }
            return true
        }
    }

    @ViewBuilder
    private var syncResults: some View {
        if let error = sync.errorMessage {
            Text(error)
                .foregroundStyle(.red)
                .multilineTextAlignment(.center)
        }
        if !displayItems.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                ForEach(displayItems) { item in
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
        } else if sync.errorMessage == nil, sync.lastSyncFinishedAt != nil {
            emptySyncMessage
        }
    }

    // Possible duplicate HealthKit workouts found this sync (#39). Read-only —
    // we can't delete other apps' samples, so this just points Tom at what to
    // remove manually in the Health app.
    @ViewBuilder
    private var duplicatesSection: some View {
        if !sync.duplicateClusters.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text("Possible duplicates")
                    .font(.headline)
                    .foregroundStyle(.orange)
                Text("Same type, start, and duration as another workout. Review in the Health app and delete any extras.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                ForEach(sync.duplicateClusters) { cluster in
                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(typeName(cluster.members[0].activityType)) · \(cluster.members[0].startDate.formatted(date: .abbreviated, time: .shortened))")
                            .font(.subheadline.bold())
                        ForEach(cluster.members) { member in
                            Text("• \(member.sourceName) · \(durationLabel(member.duration))\(distanceSuffix(member.distanceMeters))")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    Divider()
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func durationLabel(_ seconds: TimeInterval) -> String {
        let total = Int(seconds.rounded())
        return String(format: "%d:%02d", total / 60, total % 60)
    }

    private func distanceSuffix(_ meters: Double?) -> String {
        guard let meters, meters > 0 else { return "" }
        return String(format: " · %.2f mi", meters / 1609.344)
    }

    private func typeName(_ type: HKWorkoutActivityType) -> String {
        switch type {
        case .cycling: return "Cycling"
        case .running: return "Running"
        case .walking: return "Walking"
        case .hiking: return "Hiking"
        case .swimming: return "Swimming"
        case .traditionalStrengthTraining: return "Strength"
        default: return "Workout"
        }
    }

    @ViewBuilder
    private var emptySyncMessage: some View {
        let label: String = {
            // Read from the orchestrator's snapshot, NOT SyncCheckpoint.load() —
            // by the time this renders, the live checkpoint has already
            // advanced to the just-completed sync's time (#30).
            if let prior = sync.priorCheckpoint {
                return "No new activities since \(prior.formatted(date: .abbreviated, time: .shortened))"
            }
            return "No new activities."
        }()
        Text(label)
            .font(.caption)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private func statusLabel(for status: SyncOrchestrator.ItemStatus) -> some View {
        switch status {
        case .pending:
            Text("…").foregroundStyle(.secondary)
        case .written(let effort):
            Text("Effort \(effort, specifier: "%.0f")").foregroundStyle(.green)
        case .writtenWithDistance(let effort):
            Text("Effort \(effort, specifier: "%.0f") + dist").foregroundStyle(.green)
        case .addedDistance:
            Text("+ Distance").foregroundStyle(.green)
        case .writtenAsNew(let effort):
            Text("Created + Effort \(effort, specifier: "%.0f")").foregroundStyle(.green)
        case .deferredAwaitingHKTwin:
            Text("Deferred (awaiting HK)").foregroundStyle(.orange)
        case .healedDuplicate(let effort):
            Text("Removed dup + Effort \(effort, specifier: "%.0f")").foregroundStyle(.green)
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
                    let expandable = !entry.items.isEmpty
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 8) {
                            sourcePill(for: entry.source)
                            Text(entry.timestamp.formatted(date: .abbreviated, time: .shortened))
                                .font(.caption)
                            Spacer()
                            Text(syncedCountLabel(for: entry))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            if entry.perItemErrors > 0 || entry.errorSummary != nil {
                                Text("⚠")
                                    .foregroundStyle(.orange)
                            }
                            if expandable {
                                Image(systemName: expandedSyncIDs.contains(entry.id) ? "chevron.down" : "chevron.right")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .contentShape(Rectangle())
                        .onTapGesture {
                            guard expandable else { return }
                            withAnimation { toggleExpanded(entry.id) }
                        }
                        if let detail = entry.errorSummary ?? entry.firstItemError {
                            Text(detail)
                                .font(.caption2)
                                .foregroundStyle(.red)
                        }
                        if expandedSyncIDs.contains(entry.id) {
                            ForEach(entry.items) { item in
                                HStack(alignment: .top, spacing: 8) {
                                    VStack(alignment: .leading, spacing: 0) {
                                        Text(item.name)
                                            .font(.caption)
                                        Text(item.startDate.formatted(date: .abbreviated, time: .shortened))
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    Text(item.outcome)
                                        .font(.caption2)
                                        .foregroundStyle(item.wasWritten ? .green : .secondary)
                                        .multilineTextAlignment(.trailing)
                                }
                                .padding(.leading, 8)
                            }
                        }
                    }
                    Divider()
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // Headline number on a Recent syncs row. New entries (#41) carry per-item
    // data, so we show activities actually *written* — a skip-only overlap
    // re-fetch reads "0 synced" instead of the old misleading "1 activity".
    // Legacy entries have no items array; fall back to the prior count.
    private func syncedCountLabel(for entry: SyncLogEntry) -> String {
        guard !entry.items.isEmpty else {
            return "\(entry.activitiesProcessed) activities"
        }
        let synced = entry.items.filter(\.wasWritten).count
        return "\(synced) synced"
    }

    private func toggleExpanded(_ id: UUID) {
        if expandedSyncIDs.contains(id) {
            expandedSyncIDs.remove(id)
        } else {
            expandedSyncIDs.insert(id)
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
