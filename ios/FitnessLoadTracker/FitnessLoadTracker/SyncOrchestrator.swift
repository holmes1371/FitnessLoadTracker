//
//  SyncOrchestrator.swift
//  FitnessLoadTracker
//

import Foundation
import HealthKit
import Observation

@Observable
final class SyncOrchestrator {
    enum ItemStatus: Equatable {
        case pending
        case written(effort: Double)
        case skippedNoSufferScore
        case skippedNoMatch
        case skippedMultipleMatches
        case skippedAlreadyHasEffort
        case error(String)
    }

    struct Item: Identifiable, Equatable {
        let id: Int64
        let activity: StravaActivity
        var status: ItemStatus
    }

    var items: [Item] = []
    var isSyncing = false
    var errorMessage: String?

    private let client: StravaClient

    init(client: StravaClient = StravaClient()) {
        self.client = client
    }

    func syncRecentActivities(daysBack: Int = 30, healthKit: HealthKitManager) async {
        isSyncing = true
        errorMessage = nil
        items = []
        defer { isSyncing = false }

        guard let refreshToken = Keychain.load() else {
            errorMessage = "Not connected to Strava."
            return
        }

        do {
            let tokens = try await client.refreshAccessToken(refreshToken: refreshToken)
            try Keychain.save(tokens.refreshToken)

            let after = Date(timeIntervalSinceNow: -Double(daysBack) * 86_400)
            let activities = try await client.fetchActivities(accessToken: tokens.accessToken, after: after)

            items = activities.map { Item(id: $0.id, activity: $0, status: .pending) }

            for index in items.indices {
                await process(itemIndex: index, healthKit: healthKit)
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func process(itemIndex: Int, healthKit: HealthKitManager) async {
        let activity = items[itemIndex].activity

        guard let sufferScore = activity.sufferScore else {
            items[itemIndex].status = .skippedNoSufferScore
            return
        }
        guard let effort = Calibration.effort(forSufferScore: sufferScore) else {
            items[itemIndex].status = .skippedNoSufferScore
            return
        }

        do {
            let window: TimeInterval = 5 * 60
            let start = activity.startDate.addingTimeInterval(-window)
            let end = activity.startDate.addingTimeInterval(TimeInterval(activity.elapsedTime) + window)
            let workouts = try await healthKit.workouts(in: start...end)
            let candidates = workouts.map {
                WorkoutCandidate(
                    startDate: $0.startDate,
                    duration: $0.duration,
                    activityType: $0.workoutActivityType
                )
            }
            switch Matching.findMatch(for: activity, in: candidates) {
            case .matched(let i):
                let workout = workouts[i]
                if try await healthKit.hasEffortScore(for: workout) {
                    items[itemIndex].status = .skippedAlreadyHasEffort
                } else {
                    try await healthKit.writeEffort(effort, on: workout)
                    items[itemIndex].status = .written(effort: effort)
                }
            case .noMatch:
                items[itemIndex].status = .skippedNoMatch
            case .multipleMatches:
                items[itemIndex].status = .skippedMultipleMatches
            }
        } catch {
            items[itemIndex].status = .error(error.localizedDescription)
        }
    }
}
