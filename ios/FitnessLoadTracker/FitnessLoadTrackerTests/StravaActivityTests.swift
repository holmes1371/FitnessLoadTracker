//
//  StravaActivityTests.swift
//  FitnessLoadTrackerTests
//

import Foundation
import Testing
@testable import FitnessLoadTracker

@Suite("StravaActivity decoding")
struct StravaActivityTests {
    @Test("decodes typical ride with suffer score")
    func typicalRide() throws {
        let json = """
        [{
            "id": 1234567890,
            "name": "Morning Ride",
            "sport_type": "Ride",
            "start_date": "2026-05-20T13:00:00Z",
            "elapsed_time": 3600,
            "moving_time": 3550,
            "suffer_score": 87.5
        }]
        """.data(using: .utf8)!

        let activities = try StravaClient.decodeActivities(from: json)
        #expect(activities.count == 1)
        let a = activities[0]
        #expect(a.id == 1_234_567_890)
        #expect(a.name == "Morning Ride")
        #expect(a.sportType == "Ride")
        #expect(a.elapsedTime == 3600)
        #expect(a.movingTime == 3550)
        #expect(a.sufferScore == 87.5)
    }

    @Test("tolerates null suffer score (activity without HR data)")
    func nullSufferScore() throws {
        let json = """
        [{
            "id": 1,
            "name": "Indoor cool-down",
            "sport_type": "Ride",
            "start_date": "2026-05-20T13:00:00Z",
            "elapsed_time": 600,
            "moving_time": 600,
            "suffer_score": null
        }]
        """.data(using: .utf8)!

        let activities = try StravaClient.decodeActivities(from: json)
        #expect(activities[0].sufferScore == nil)
    }

    @Test("decodes Walk sport type")
    func walk() throws {
        let json = """
        [{
            "id": 2,
            "name": "Evening Walk",
            "sport_type": "Walk",
            "start_date": "2026-05-21T19:30:00Z",
            "elapsed_time": 1800,
            "moving_time": 1750,
            "suffer_score": null
        }]
        """.data(using: .utf8)!

        let activities = try StravaClient.decodeActivities(from: json)
        #expect(activities[0].sportType == "Walk")
        #expect(activities[0].sufferScore == nil)
    }
}
