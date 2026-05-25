//
//  HealthKitManagerTests.swift
//  FitnessLoadTrackerTests
//

import Foundation
import HealthKit
import Testing
@testable import FitnessLoadTracker

@Suite("HealthKitManager")
struct HealthKitManagerTests {
    @Test("Share set authorizes workouts, effort score, and heart rate")
    func shareSetContents() {
        #expect(HealthKitManager.shareTypes.contains(HKWorkoutType.workoutType()))
        #expect(HealthKitManager.shareTypes.contains(HKQuantityType(.workoutEffortScore)))
        #expect(HealthKitManager.shareTypes.contains(HKQuantityType(.heartRate)))
    }

    @Test("Read set authorizes workouts and effort score")
    func readSetContents() {
        #expect(HealthKitManager.readTypes.contains(HKWorkoutType.workoutType()))
        #expect(HealthKitManager.readTypes.contains(HKQuantityType(.workoutEffortScore)))
    }
}

@Suite("HealthKitManager.buildWorkoutData")
struct HealthKitManagerBuildWorkoutDataTests {
    private let p = HealthKitManager.customMetadataPrefix
    private let speedUnit = HKUnit.meter().unitDivided(by: .second())
    private let hrUnit = HKUnit.count().unitDivided(by: .minute())

    @Test("builds cycling workout from full detail + HR stream")
    func cyclingFullBuild() throws {
        let start = Date(timeIntervalSince1970: 1_780_000_000)
        let detail = makeCyclingDetail(startDate: start)
        let streams = makeHRStream(count: 3600)

        let build = try HealthKitManager.buildWorkoutData(detail: detail, streams: streams)

        #expect(build.workout.workoutActivityType == .cycling)
        #expect(build.workout.startDate == start)
        #expect(build.workout.duration == TimeInterval(detail.movingTime))
        #expect(build.workout.endDate == start.addingTimeInterval(TimeInterval(detail.movingTime)))
        #expect(build.workout.totalDistance == HKQuantity(unit: .meter(), doubleValue: detail.distance))
        #expect(build.workout.totalEnergyBurned == HKQuantity(unit: .kilocalorie(), doubleValue: detail.calories))

        let md = try #require(build.workout.metadata)
        #expect((md[HKMetadataKeyAverageSpeed] as? HKQuantity)?.doubleValue(for: speedUnit) == detail.averageSpeed)
        #expect((md[HKMetadataKeyMaximumSpeed] as? HKQuantity)?.doubleValue(for: speedUnit) == detail.maxSpeed)
        #expect((md[HKMetadataKeyElevationAscended] as? HKQuantity)?.doubleValue(for: .meter()) == detail.totalElevationGain)
        #expect(md["\(p)elapsedTime"] as? Int == detail.elapsedTime)
        #expect(md["\(p)stravaActivityId"] as? Int64 == detail.id)
        #expect(md["\(p)avgHeartRate"] as? Double == detail.averageHeartrate)
        #expect(md["\(p)maxHeartRate"] as? Double == detail.maxHeartrate)
        #expect(md["\(p)avgCadence"] as? Double == detail.averageCadence)
        #expect(md["\(p)avgWatts"] as? Double == detail.averageWatts)
        #expect(md["\(p)maxWatts"] as? Int == detail.maxWatts)
        #expect(md["\(p)weightedAvgWatts"] as? Int == detail.weightedAverageWatts)
        #expect(md["\(p)kilojoules"] as? Double == detail.kilojoules)
        #expect(md["\(p)deviceName"] as? String == detail.deviceName)
        #expect(md["\(p)stravaWorkoutType"] as? Int == detail.workoutType)

        #expect(build.heartRateSamples.count == 3600)
        let first = try #require(build.heartRateSamples.first)
        #expect(first.startDate == start)
        #expect(first.endDate == start)
        #expect(first.quantity.doubleValue(for: hrUnit) == 120)
        let last = try #require(build.heartRateSamples.last)
        #expect(last.startDate == start.addingTimeInterval(3599))
        #expect(last.quantity.doubleValue(for: hrUnit) == Double(120 + (3599 % 50)))
    }

    @Test("omits optional metadata keys when source fields are nil")
    func walkOmitsOptionals() throws {
        let detail = StravaActivityDetail(
            id: 42,
            name: "Walk",
            sportType: "Walk",
            startDate: Date(timeIntervalSince1970: 1_780_000_000),
            startDateLocal: Date(timeIntervalSince1970: 1_780_000_000),
            elapsedTime: 1800,
            movingTime: 1750,
            distance: 2200,
            totalElevationGain: 12,
            averageSpeed: 1.26,
            maxSpeed: 1.65,
            averageHeartrate: nil,
            maxHeartrate: nil,
            calories: 145,
            deviceName: nil,
            workoutType: nil,
            averageCadence: nil,
            averageWatts: nil,
            maxWatts: nil,
            weightedAverageWatts: nil,
            kilojoules: nil
        )
        let streams = StravaStreams(heartrate: nil, time: nil)

        let build = try HealthKitManager.buildWorkoutData(detail: detail, streams: streams)

        #expect(build.workout.workoutActivityType == .walking)
        let md = try #require(build.workout.metadata)
        // First-class metadata always written
        #expect(md[HKMetadataKeyAverageSpeed] != nil)
        #expect(md[HKMetadataKeyElevationAscended] != nil)
        // Required custom metadata always written
        #expect(md["\(p)elapsedTime"] != nil)
        #expect(md["\(p)stravaActivityId"] != nil)
        // Optional custom metadata absent when source nil
        #expect(md["\(p)avgHeartRate"] == nil)
        #expect(md["\(p)maxHeartRate"] == nil)
        #expect(md["\(p)avgCadence"] == nil)
        #expect(md["\(p)avgWatts"] == nil)
        #expect(md["\(p)maxWatts"] == nil)
        #expect(md["\(p)weightedAvgWatts"] == nil)
        #expect(md["\(p)kilojoules"] == nil)
        #expect(md["\(p)deviceName"] == nil)
        #expect(md["\(p)stravaWorkoutType"] == nil)
        #expect(build.heartRateSamples.isEmpty)
    }

    @Test("produces empty HR samples when stream has no heartrate channel")
    func noHRStream() throws {
        let detail = makeCyclingDetail(startDate: Date(timeIntervalSince1970: 1_780_000_000))
        let streams = StravaStreams(
            heartrate: nil,
            time: StravaStreams.Stream(data: [0, 1, 2], seriesType: "time", originalSize: 3, resolution: "high")
        )

        let build = try HealthKitManager.buildWorkoutData(detail: detail, streams: streams)
        #expect(build.heartRateSamples.isEmpty)
        #expect(build.workout.workoutActivityType == .cycling)
    }

    @Test("throws unmappedSportType for sport types Matching doesn't know")
    func unmappedSportThrows() {
        let detail = makeCyclingDetail(startDate: Date(), sportType: "Yoga")
        let streams = StravaStreams(heartrate: nil, time: nil)
        #expect(throws: HealthKitManager.WriteWorkoutError.self) {
            _ = try HealthKitManager.buildWorkoutData(detail: detail, streams: streams)
        }
    }

    // MARK: - Helpers

    private func makeCyclingDetail(
        startDate: Date,
        sportType: String = "Ride"
    ) -> StravaActivityDetail {
        StravaActivityDetail(
            id: 9_876_543_210,
            name: "Lunch Ride",
            sportType: sportType,
            startDate: startDate,
            startDateLocal: startDate,
            elapsedTime: 3650,
            movingTime: 3600,
            distance: 32_184,
            totalElevationGain: 420.5,
            averageSpeed: 8.94,
            maxSpeed: 17.21,
            averageHeartrate: 145.3,
            maxHeartrate: 178.0,
            calories: 820.5,
            deviceName: "Garmin Edge 1040",
            workoutType: 10,
            averageCadence: 84.2,
            averageWatts: 187.4,
            maxWatts: 612,
            weightedAverageWatts: 201,
            kilojoules: 674.6
        )
    }

    private func makeHRStream(count: Int) -> StravaStreams {
        let hr = (0..<count).map { 120 + ($0 % 50) }
        let times = Array(0..<count)
        return StravaStreams(
            heartrate: StravaStreams.Stream(data: hr, seriesType: "time", originalSize: count, resolution: "high"),
            time: StravaStreams.Stream(data: times, seriesType: "time", originalSize: count, resolution: "high")
        )
    }
}
