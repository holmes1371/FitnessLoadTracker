//
//  ContentView.swift
//  FitnessLoadTracker
//

import SwiftUI
import HealthKit

struct ContentView: View {
    @State private var manager = HealthKitManager()
    @State private var strava = StravaConnection()
    @State private var sync = SyncOrchestrator()
    @State private var showingProbe = false

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                Text("FitnessLoadTracker")
                    .font(.title)

                stravaSection

                Divider()

                debugButton

                probeButton

                statusView
            }
            .padding()
        }
        .task {
            await manager.requestAuthorization()
        }
        .sheet(isPresented: $showingProbe) {
            ProbeSheet(manager: manager)
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

    private var probeButton: some View {
        Button {
            showingProbe = true
        } label: {
            Text("POC: Probe HealthKit sources (#12)")
                .padding()
                .frame(maxWidth: .infinity)
                .background(Color.purple.opacity(0.7))
                .foregroundStyle(.white)
                .clipShape(RoundedRectangle(cornerRadius: 12))
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
}

#Preview {
    ContentView()
}

// MARK: - POC probe sheet (#12)

private struct ProbeSheet: View {
    let manager: HealthKitManager

    @Environment(\.dismiss) private var dismiss
    @State private var rows: [HealthKitManager.ProbeRow] = []
    @State private var rowStatus: [UUID: String] = [:]
    @State private var loadError: String?
    @State private var loading = true

    var body: some View {
        NavigationStack {
            content
                .navigationTitle("HealthKit probe")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Close") { dismiss() }
                    }
                }
                .task { await load() }
        }
    }

    @ViewBuilder
    private var content: some View {
        if loading {
            ProgressView("Loading last 90 days…")
        } else if let loadError {
            ScrollView {
                Text(loadError)
                    .foregroundStyle(.red)
                    .padding()
            }
        } else if rows.isEmpty {
            Text("No workouts in the last 90 days.")
                .foregroundStyle(.secondary)
                .padding()
        } else {
            List(rows) { row in
                rowView(row)
            }
            .listStyle(.plain)
        }
    }

    @ViewBuilder
    private func rowView(_ row: HealthKitManager.ProbeRow) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(activityName(row.workout.workoutActivityType))
                .font(.subheadline.bold())
            Text(row.workout.startDate.formatted(date: .abbreviated, time: .shortened))
                .font(.caption)
                .foregroundStyle(.secondary)
            Text("Source: \(row.sourceName)")
                .font(.caption)
            HStack(spacing: 8) {
                Text(row.bundleID)
                    .font(.caption.monospaced())
                    .lineLimit(1)
                    .truncationMode(.middle)
                Button {
                    UIPasteboard.general.string = row.bundleID
                } label: {
                    Image(systemName: "doc.on.doc")
                }
                .buttonStyle(.borderless)
            }
            HStack {
                Button(role: .destructive) {
                    Task { await delete(row) }
                } label: {
                    Text("Delete")
                }
                .buttonStyle(.bordered)

                if let status = rowStatus[row.id] {
                    Text(status)
                        .font(.caption)
                        .foregroundStyle(status.hasPrefix("deleted") ? .green : .red)
                }
            }
        }
        .padding(.vertical, 4)
    }

    private func load() async {
        loading = true
        loadError = nil
        do {
            rows = try await manager.recentWorkoutsWithSource(days: 90)
        } catch {
            loadError = error.localizedDescription
        }
        loading = false
    }

    private func delete(_ row: HealthKitManager.ProbeRow) async {
        do {
            try await manager.deleteWorkout(row.workout)
            rowStatus[row.id] = "deleted"
        } catch {
            let ns = error as NSError
            rowStatus[row.id] = "error: \(ns.domain) \(ns.code) — \(ns.localizedDescription)"
        }
    }

    private func activityName(_ type: HKWorkoutActivityType) -> String {
        switch type {
        case .cycling: return "Cycling"
        case .running: return "Running"
        case .walking: return "Walking"
        case .hiking: return "Hiking"
        case .swimming: return "Swimming"
        case .functionalStrengthTraining: return "Functional strength"
        case .traditionalStrengthTraining: return "Strength"
        case .yoga: return "Yoga"
        case .rowing: return "Rowing"
        case .stairClimbing: return "Stair climbing"
        case .elliptical: return "Elliptical"
        case .mixedCardio: return "Mixed cardio"
        case .highIntensityIntervalTraining: return "HIIT"
        default: return "Type \(type.rawValue)"
        }
    }
}
