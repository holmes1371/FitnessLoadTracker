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
    @Test("Share set authorizes every type the builder writes")
    func shareSetContents() {
        #expect(HealthKitManager.shareTypes.contains(HKWorkoutType.workoutType()))
        #expect(HealthKitManager.shareTypes.contains(HKQuantityType(.workoutEffortScore)))
        #expect(HealthKitManager.shareTypes.contains(HKQuantityType(.heartRate)))
        #expect(HealthKitManager.shareTypes.contains(HKQuantityType(.activeEnergyBurned)))
        #expect(HealthKitManager.shareTypes.contains(HKQuantityType(.distanceCycling)))
        #expect(HealthKitManager.shareTypes.contains(HKQuantityType(.distanceWalkingRunning)))
        #expect(HealthKitManager.shareTypes.contains(HKQuantityType(.distanceSwimming)))
    }

    @Test("Read set authorizes workouts and effort score")
    func readSetContents() {
        #expect(HealthKitManager.readTypes.contains(HKWorkoutType.workoutType()))
        #expect(HealthKitManager.readTypes.contains(HKQuantityType(.workoutEffortScore)))
    }

    @Test("distanceQuantityType maps each Matching activity type to the right cumulative distance type")
    func distanceQuantityTypeMapping() {
        #expect(HealthKitManager.distanceQuantityType(for: .cycling) == HKQuantityType(.distanceCycling))
        #expect(HealthKitManager.distanceQuantityType(for: .swimming) == HKQuantityType(.distanceSwimming))
        #expect(HealthKitManager.distanceQuantityType(for: .running) == HKQuantityType(.distanceWalkingRunning))
        #expect(HealthKitManager.distanceQuantityType(for: .walking) == HKQuantityType(.distanceWalkingRunning))
        #expect(HealthKitManager.distanceQuantityType(for: .hiking) == HKQuantityType(.distanceWalkingRunning))
    }
}

@Suite("HealthKitManager.buildBlueprint")
struct HealthKitManagerBuildBlueprintTests {
    private let p = HealthKitManager.customMetadataPrefix
    private let speedUnit = HKUnit.meter().unitDivided(by: .second())
    private let hrUnit = HKUnit.count().unitDivided(by: .minute())

    @Test("builds cycling blueprint from full detail + HR stream")
    func cyclingFullBuild() throws {
        let start = Date(timeIntervalSince1970: 1_780_000_000)
        let detail = makeCyclingDetail(startDate: start)
        let streams = makeHRStream(count: 3600)

        let blueprint = try HealthKitManager.buildBlueprint(detail: detail, streams: streams)

        #expect(blueprint.activityType == .cycling)
        #expect(blueprint.startDate == start)
        #expect(blueprint.duration == TimeInterval(detail.movingTime))
        #expect(blueprint.endDate == start.addingTimeInterval(TimeInterval(detail.movingTime)))
        #expect(blueprint.totalDistance == HKQuantity(unit: .meter(), doubleValue: detail.distance))
        #expect(blueprint.totalEnergyBurned == HKQuantity(unit: .kilocalorie(), doubleValue: detail.calories))

        let md = blueprint.metadata
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

        #expect(blueprint.heartRateSamples.count == 3600)
        let first = try #require(blueprint.heartRateSamples.first)
        #expect(first.startDate == start)
        #expect(first.endDate == start)
        #expect(first.quantity.doubleValue(for: hrUnit) == 120)
        let last = try #require(blueprint.heartRateSamples.last)
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
            kilojoules: nil,
            sufferScore: nil
        )
        let streams = StravaStreams(heartrate: nil, time: nil)

        let blueprint = try HealthKitManager.buildBlueprint(detail: detail, streams: streams)

        #expect(blueprint.activityType == .walking)
        let md = blueprint.metadata
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
        #expect(blueprint.heartRateSamples.isEmpty)
    }

    @Test("produces empty HR samples when stream has no heartrate channel")
    func noHRStream() throws {
        let detail = makeCyclingDetail(startDate: Date(timeIntervalSince1970: 1_780_000_000))
        let streams = StravaStreams(
            heartrate: nil,
            time: StravaStreams.Stream(data: [0, 1, 2], seriesType: "time", originalSize: 3, resolution: "high")
        )

        let blueprint = try HealthKitManager.buildBlueprint(detail: detail, streams: streams)
        #expect(blueprint.heartRateSamples.isEmpty)
        #expect(blueprint.activityType == .cycling)
    }

    @Test("throws unmappedSportType for sport types Matching doesn't know")
    func unmappedSportThrows() {
        let detail = makeCyclingDetail(startDate: Date(), sportType: "Yoga")
        let streams = StravaStreams(heartrate: nil, time: nil)
        #expect(throws: HealthKitManager.WriteWorkoutError.self) {
            _ = try HealthKitManager.buildBlueprint(detail: detail, streams: streams)
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
            kilojoules: 674.6,
            sufferScore: 87.5
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
