//
//  Matching.swift
//  FitnessLoadTracker
//
//  Match a Strava activity to a HealthKit workout per design/architecture.md:
//    start_time within ±60s, duration within ±60s, activity type matches.
//  Operates on plain structs so the matching is unit-testable without HKWorkout.
//

import Foundation
import HealthKit

struct WorkoutCandidate: Equatable {
    let startDate: Date
    let duration: TimeInterval
    let activityType: HKWorkoutActivityType
}

enum MatchResult: Equatable {
    case matched(index: Int)
    case noMatch
    case multipleMatches
}

enum Matching {
    static let toleranceSeconds: TimeInterval = 60

    static func hkActivityType(forStravaSportType sportType: String) -> HKWorkoutActivityType? {
        switch sportType {
        case "Ride", "VirtualRide", "MountainBikeRide", "GravelRide", "EBikeRide",
             "EMountainBikeRide", "Velomobile":
            return .cycling
        case "Run", "VirtualRun", "TrailRun":
            return .running
        case "Walk":
            return .walking
        case "Hike":
            return .hiking
        case "Swim":
            return .swimming
        default:
            return nil
        }
    }

    static func findMatch(for activity: StravaActivity, in candidates: [WorkoutCandidate]) -> MatchResult {
        guard let targetType = hkActivityType(forStravaSportType: activity.sportType) else {
            return .noMatch
        }
        let activityDuration = TimeInterval(activity.elapsedTime)
        let matches = candidates.enumerated().filter { _, candidate in
            candidate.activityType == targetType &&
            abs(candidate.startDate.timeIntervalSince(activity.startDate)) <= toleranceSeconds &&
            abs(candidate.duration - activityDuration) <= toleranceSeconds
        }
        switch matches.count {
        case 0:  return .noMatch
        case 1:  return .matched(index: matches[0].offset)
        default: return .multipleMatches
        }
    }
}
