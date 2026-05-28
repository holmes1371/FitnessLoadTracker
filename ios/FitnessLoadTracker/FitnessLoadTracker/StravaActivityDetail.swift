//
//  StravaActivityDetail.swift
//  FitnessLoadTracker
//

import Foundation

// Response from /api/v3/activities/{id}. Superset of /athlete/activities;
// carries the fields needed to populate an app-authored HKWorkout for a
// Strava-only activity (calories, device_name, workout_type, cycling
// power/cadence) alongside the summary-endpoint fields we want as HK
// metadata (distance, elevation, HR avg/max, speed avg/max).
struct StravaActivityDetail: Decodable, Equatable {
    let id: Int64
    let name: String
    let sportType: String
    let startDate: Date
    let startDateLocal: Date
    let elapsedTime: Int
    let movingTime: Int
    let distance: Double
    let totalElevationGain: Double
    let averageSpeed: Double
    let maxSpeed: Double
    let averageHeartrate: Double?
    let maxHeartrate: Double?
    let calories: Double
    let deviceName: String?
    let workoutType: Int?
    let averageCadence: Double?
    let averageWatts: Double?
    let maxWatts: Int?
    let weightedAverageWatts: Int?
    let kilojoules: Double?
    let sufferScore: Double?

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case sportType = "sport_type"
        case startDate = "start_date"
        case startDateLocal = "start_date_local"
        case elapsedTime = "elapsed_time"
        case movingTime = "moving_time"
        case distance
        case totalElevationGain = "total_elevation_gain"
        case averageSpeed = "average_speed"
        case maxSpeed = "max_speed"
        case averageHeartrate = "average_heartrate"
        case maxHeartrate = "max_heartrate"
        case calories
        case deviceName = "device_name"
        case workoutType = "workout_type"
        case averageCadence = "average_cadence"
        case averageWatts = "average_watts"
        case maxWatts = "max_watts"
        case weightedAverageWatts = "weighted_average_watts"
        case kilojoules
        case sufferScore = "suffer_score"
    }
}

extension StravaActivityDetail {
    // Project the detail-endpoint response down to the summary-endpoint
    // shape so callers that already have a Detail (e.g. the targeted
    // single-activity sync path) can feed it through the existing
    // matching/orchestration pipeline without a redundant list-endpoint
    // fetch.
    var asSummary: StravaActivity {
        StravaActivity(
            id: id,
            name: name,
            sportType: sportType,
            startDate: startDate,
            elapsedTime: elapsedTime,
            movingTime: movingTime,
            distance: distance,
            sufferScore: sufferScore
        )
    }
}
