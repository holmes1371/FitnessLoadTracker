//
//  StravaActivity.swift
//  FitnessLoadTracker
//

import Foundation

struct StravaActivity: Decodable, Equatable, Identifiable {
    let id: Int64
    let name: String
    let sportType: String
    let startDate: Date
    let elapsedTime: Int
    let movingTime: Int
    let sufferScore: Double?

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case sportType = "sport_type"
        case startDate = "start_date"
        case elapsedTime = "elapsed_time"
        case movingTime = "moving_time"
        case sufferScore = "suffer_score"
    }
}
