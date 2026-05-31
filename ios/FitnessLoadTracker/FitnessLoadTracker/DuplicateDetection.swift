//
//  DuplicateDetection.swift
//  FitnessLoadTracker
//
//  Find HealthKit workouts that look like the same real-world activity recorded
//  twice — typically because a second app (Strava alongside Peloton / Apple
//  Watch) wrote its own copy (#39). We can't delete other apps' samples (#12),
//  so this only flags clusters for manual review in the Health app.
//
//  Operates on plain structs so the clustering is unit-testable without HKWorkout.
//

import Foundation
import HealthKit

struct WorkoutForDuplicateCheck: Identifiable, Equatable {
    let id: UUID
    let startDate: Date
    let duration: TimeInterval
    let activityType: HKWorkoutActivityType
    let sourceName: String
    // Display corroboration only — NOT used to decide a duplicate, so a ride
    // whose source carries no distance still pairs with its twin.
    let distanceMeters: Double?
}

struct DuplicateCluster: Identifiable, Equatable {
    let members: [WorkoutForDuplicateCheck]
    // Stable across re-detection of the same pair: the sorted member ids. Lets
    // the orchestrator dedup clusters surfaced by overlapping per-activity windows.
    var id: String { members.map(\.id.uuidString).sorted().joined(separator: "|") }
}

enum DuplicateDetection {
    // Same tolerances Matching uses to call a Strava activity and an HK workout
    // the same session — two HK workouts that close are the same session twice.
    static let toleranceSeconds: TimeInterval = 60

    // Two workouts look like the same activity when they share a type and fall
    // within tolerance on both start and duration. Distance is ignored here.
    static func isDuplicatePair(_ a: WorkoutForDuplicateCheck, _ b: WorkoutForDuplicateCheck) -> Bool {
        a.activityType == b.activityType &&
        abs(a.startDate.timeIntervalSince(b.startDate)) <= toleranceSeconds &&
        abs(a.duration - b.duration) <= toleranceSeconds
    }

    // Group workouts into clusters of 2+ that pairwise look like duplicates.
    // Uses simple union-find: "within tolerance" isn't transitive, but at the
    // scale here (a handful of workouts in one activity's window) any reasonable
    // grouping is equivalent. Singletons are dropped.
    static func clusters(in workouts: [WorkoutForDuplicateCheck]) -> [DuplicateCluster] {
        var parent = Array(workouts.indices)
        func find(_ i: Int) -> Int {
            var root = i
            while parent[root] != root { root = parent[root] }
            var node = i
            while parent[node] != node { let next = parent[node]; parent[node] = root; node = next }
            return root
        }
        for i in workouts.indices {
            for j in (i + 1)..<workouts.count where isDuplicatePair(workouts[i], workouts[j]) {
                parent[find(j)] = find(i)
            }
        }
        var groups: [Int: [WorkoutForDuplicateCheck]] = [:]
        for i in workouts.indices {
            groups[find(i), default: []].append(workouts[i])
        }
        return groups.values
            .filter { $0.count >= 2 }
            .map { DuplicateCluster(members: $0.sorted { $0.startDate < $1.startDate }) }
            .sorted { $0.members[0].startDate < $1.members[0].startDate }
    }
}
