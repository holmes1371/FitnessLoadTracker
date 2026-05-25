//
//  StravaActivityDetailTests.swift
//  FitnessLoadTrackerTests
//

import Foundation
import Testing
@testable import FitnessLoadTracker

@Suite("StravaActivityDetail decoding")
struct StravaActivityDetailTests {
    @Test("decodes outdoor ride with full power/cadence/HR payload")
    func outdoorRide() throws {
        let json = """
        {
            "id": 9876543210,
            "name": "Lunch Ride",
            "sport_type": "Ride",
            "start_date": "2026-05-20T17:00:00Z",
            "start_date_local": "2026-05-20T13:00:00Z",
            "elapsed_time": 3650,
            "moving_time": 3600,
            "distance": 32184.0,
            "total_elevation_gain": 420.5,
            "average_speed": 8.94,
            "max_speed": 17.21,
            "average_heartrate": 145.3,
            "max_heartrate": 178.0,
            "calories": 820.5,
            "device_name": "Garmin Edge 1040",
            "workout_type": 10,
            "average_cadence": 84.2,
            "average_watts": 187.4,
            "max_watts": 612,
            "weighted_average_watts": 201,
            "kilojoules": 674.6
        }
        """.data(using: .utf8)!

        let d = try StravaClient.decodeActivityDetail(from: json)
        #expect(d.id == 9_876_543_210)
        #expect(d.name == "Lunch Ride")
        #expect(d.sportType == "Ride")
        #expect(d.elapsedTime == 3650)
        #expect(d.movingTime == 3600)
        #expect(d.distance == 32_184.0)
        #expect(d.totalElevationGain == 420.5)
        #expect(d.averageSpeed == 8.94)
        #expect(d.maxSpeed == 17.21)
        #expect(d.averageHeartrate == 145.3)
        #expect(d.maxHeartrate == 178.0)
        #expect(d.calories == 820.5)
        #expect(d.deviceName == "Garmin Edge 1040")
        #expect(d.workoutType == 10)
        #expect(d.averageCadence == 84.2)
        #expect(d.averageWatts == 187.4)
        #expect(d.maxWatts == 612)
        #expect(d.weightedAverageWatts == 201)
        #expect(d.kilojoules == 674.6)
        // start_date drift between UTC and start_date_local should round-trip
        // independently so step 4 can pick whichever it wants.
        #expect(d.startDate != d.startDateLocal)
    }

    @Test("tolerates missing optional power/cadence/HR/workout-type fields")
    func walkWithoutPower() throws {
        let json = """
        {
            "id": 100,
            "name": "Evening Walk",
            "sport_type": "Walk",
            "start_date": "2026-05-21T23:30:00Z",
            "start_date_local": "2026-05-21T19:30:00Z",
            "elapsed_time": 1800,
            "moving_time": 1750,
            "distance": 2200.0,
            "total_elevation_gain": 12.0,
            "average_speed": 1.26,
            "max_speed": 1.65,
            "calories": 145.0
        }
        """.data(using: .utf8)!

        let d = try StravaClient.decodeActivityDetail(from: json)
        #expect(d.sportType == "Walk")
        #expect(d.calories == 145.0)
        #expect(d.averageHeartrate == nil)
        #expect(d.maxHeartrate == nil)
        #expect(d.deviceName == nil)
        #expect(d.workoutType == nil)
        #expect(d.averageCadence == nil)
        #expect(d.averageWatts == nil)
        #expect(d.maxWatts == nil)
        #expect(d.weightedAverageWatts == nil)
        #expect(d.kilojoules == nil)
    }

    @Test("tolerates explicit null on optional fields")
    func explicitNulls() throws {
        let json = """
        {
            "id": 101,
            "name": "Indoor cool-down",
            "sport_type": "Ride",
            "start_date": "2026-05-21T17:00:00Z",
            "start_date_local": "2026-05-21T13:00:00Z",
            "elapsed_time": 600,
            "moving_time": 600,
            "distance": 0.0,
            "total_elevation_gain": 0.0,
            "average_speed": 0.0,
            "max_speed": 0.0,
            "average_heartrate": null,
            "max_heartrate": null,
            "calories": 50.0,
            "device_name": null,
            "workout_type": null,
            "average_cadence": null,
            "average_watts": null,
            "max_watts": null,
            "weighted_average_watts": null,
            "kilojoules": null
        }
        """.data(using: .utf8)!

        let d = try StravaClient.decodeActivityDetail(from: json)
        #expect(d.averageHeartrate == nil)
        #expect(d.deviceName == nil)
        #expect(d.averageWatts == nil)
    }
}
