//
//  HealthKitManager.swift
//  FitnessLoadTracker
//

import Foundation
import HealthKit
import Observation

@Observable
final class HealthKitManager {
    enum Status: Equatable {
        case idle
        case working
        case success(String)
        case failure(String)
    }

    var status: Status = .idle

    private let healthStore = HKHealthStore()
    private let effortType = HKQuantityType(.workoutEffortScore)
    private let workoutType = HKWorkoutType.workoutType()

    static let shareTypes: Set<HKSampleType> = [
        HKQuantityType(.workoutEffortScore),
        HKWorkoutType.workoutType(),
        HKQuantityType(.heartRate),
        HKQuantityType(.activeEnergyBurned),
        HKQuantityType(.distanceCycling),
        HKQuantityType(.distanceWalkingRunning),
        HKQuantityType(.distanceSwimming),
    ]

    static let readTypes: Set<HKObjectType> = [
        HKQuantityType(.workoutEffortScore),
        HKWorkoutType.workoutType(),
        // Read-only, for the duplicate-workout display (#39): without read access
        // a flagged ride/run/swim's distance reads as nil and shows "—".
        HKQuantityType(.distanceCycling),
        HKQuantityType(.distanceWalkingRunning),
        HKQuantityType(.distanceSwimming),
    ]

    func requestAuthorization() async {
        do {
            try await healthStore.requestAuthorization(
                toShare: Self.shareTypes,
                read: Self.readTypes
            )
        } catch {
            status = .failure("Authorization error: \(error.localizedDescription)")
        }
    }

    func workouts(in range: ClosedRange<Date>) async throws -> [HKWorkout] {
        let datePredicate = HKQuery.predicateForSamples(withStart: range.lowerBound, end: range.upperBound)
        let descriptor = HKSampleQueryDescriptor(
            predicates: [HKSamplePredicate<HKWorkout>.workout(datePredicate)],
            sortDescriptors: [SortDescriptor(\.startDate, order: .reverse)]
        )
        return try await descriptor.result(for: healthStore)
    }

    func writeEffort(_ value: Double, on workout: HKWorkout) async throws {
        let sample = HKQuantitySample(
            type: effortType,
            quantity: HKQuantity(unit: .appleEffortScore(), doubleValue: value),
            start: workout.endDate,
            end: workout.endDate
        )
        try await healthStore.save(sample)
        do {
            try await healthStore.relateWorkoutEffortSample(sample, with: workout, activity: nil)
        } catch {
            // Honor the hard rule: an effort sample only exists when linked to a
            // workout. If linking fails, clean up the orphan before propagating.
            try? await healthStore.delete([sample])
            throw error
        }
    }

    // Metadata flag marking a near-zero-duration "proxy" workout that the
    // retired #37 distance enrichment synthesized to carry an indoor ride's
    // distance. We no longer write these (#49), but legacy proxies persist in
    // HealthKit until manually deleted — so we still recognize them to keep them
    // out of match candidates and the #43 heal.
    static let distanceProxyMetadataKey = "\(customMetadataPrefix)distanceProxy"

    func isDistanceProxy(_ workout: HKWorkout) -> Bool {
        (workout.metadata?[Self.distanceProxyMetadataKey] as? Bool) == true
    }

    func stravaActivityId(of workout: HKWorkout) -> Int64? {
        workout.metadata?["\(Self.customMetadataPrefix)stravaActivityId"] as? Int64
    }

    // The app that authored the workout — what the user sees in the Health app's
    // source list, so it identifies which copy to delete (#39).
    func sourceName(of workout: HKWorkout) -> String {
        workout.sourceRevision.source.name
    }

    // Whether this app authored the workout (vs the source app's native twin).
    // Compares bundle identifiers — HKSource.default() is the current app's
    // source. Drives the #43 heal's native-vs-our-copy distinction.
    func isAppAuthored(_ workout: HKWorkout) -> Bool {
        workout.sourceRevision.source.bundleIdentifier == HKSource.default().bundleIdentifier
    }

    // Delete a workout this app authored along with the samples it owns — the
    // HR / energy / distance collected into it, plus any related effort. Used to
    // heal a duplicate our create path authored before the source app's native
    // twin landed (#43). Guarded to our own workouts: #12 blocks deleting foreign
    // samples, and #37's retired cleanup deleted app-authored copies this way.
    // Deleting only the workout shell would orphan its samples, which keep
    // double-counting in the data-type rollups (#37).
    func deleteWorkoutWithSamples(_ workout: HKWorkout) async throws {
        guard isAppAuthored(workout) else {
            throw WriteWorkoutError.notAppAuthored
        }
        let owned = HKQuery.predicateForObjects(from: workout)
        for type in [
            HKQuantityType(.heartRate),
            HKQuantityType(.activeEnergyBurned),
            HKQuantityType(.distanceCycling),
            HKQuantityType(.distanceWalkingRunning),
            HKQuantityType(.distanceSwimming),
        ] {
            try await healthStore.deleteObjects(of: type, predicate: owned)
        }
        // Effort is related to the workout rather than collected into it, so it
        // needs its own relation predicate to avoid leaving an orphan behind.
        let effortRelated = HKQuery.predicateForWorkoutEffortSamplesRelated(
            workout: workout, activity: nil
        )
        _ = try? await healthStore.deleteObjects(of: effortType, predicate: effortRelated)
        try await healthStore.delete([workout])
    }

    // The workout's own distance in meters for the type-appropriate distance
    // sample, nil when it carries none or read access is missing. Display-only
    // corroboration on the duplicate list (#39).
    func distanceMeters(of workout: HKWorkout) -> Double? {
        let type = Self.distanceQuantityType(for: workout.workoutActivityType)
        guard let sum = workout.statistics(for: type)?.sumQuantity() else { return nil }
        return sum.doubleValue(for: .meter())
    }

    enum WriteWorkoutError: LocalizedError {
        case unmappedSportType(String)
        case builderReturnedNil
        case notAppAuthored

        var errorDescription: String? {
            switch self {
            case .unmappedSportType(let s):
                return "No HKWorkoutActivityType mapping for Strava sport type '\(s)'."
            case .builderReturnedNil:
                return "HKWorkoutBuilder.finishWorkout returned nil — workout not saved."
            case .notAppAuthored:
                return "Refused to delete a workout this app did not author."
            }
        }
    }

    struct WorkoutBlueprint {
        let activityType: HKWorkoutActivityType
        let startDate: Date
        let endDate: Date
        let duration: TimeInterval
        let totalDistance: HKQuantity
        let totalEnergyBurned: HKQuantity
        let metadata: [String: Any]
        let heartRateSamples: [HKQuantitySample]
    }

    static let customMetadataPrefix = "com.holmes.fitnessloadtracker."

    // Maps the activity types Matching can produce to the cumulative distance
    // sample type HKWorkoutBuilder expects. Kept exhaustive over Matching's
    // output so any future Matching addition forces a decision here.
    static func distanceQuantityType(for activityType: HKWorkoutActivityType) -> HKQuantityType {
        switch activityType {
        case .cycling:
            return HKQuantityType(.distanceCycling)
        case .swimming:
            return HKQuantityType(.distanceSwimming)
        default:
            return HKQuantityType(.distanceWalkingRunning)
        }
    }

    // Pure constructor — returns all the data writeWorkout will feed into
    // HKWorkoutBuilder, so tests can assert on the blueprint fields without
    // going through a real HKHealthStore.
    static func buildBlueprint(detail: StravaActivityDetail, streams: StravaStreams) throws -> WorkoutBlueprint {
        guard let activityType = Matching.hkActivityType(forStravaSportType: detail.sportType) else {
            throw WriteWorkoutError.unmappedSportType(detail.sportType)
        }
        let startDate = detail.startDate
        let duration = TimeInterval(detail.movingTime)
        let endDate = startDate.addingTimeInterval(duration)
        let speedUnit = HKUnit.meter().unitDivided(by: .second())

        var metadata: [String: Any] = [
            HKMetadataKeyAverageSpeed: HKQuantity(unit: speedUnit, doubleValue: detail.averageSpeed),
            HKMetadataKeyMaximumSpeed: HKQuantity(unit: speedUnit, doubleValue: detail.maxSpeed),
            HKMetadataKeyElevationAscended: HKQuantity(unit: .meter(), doubleValue: detail.totalElevationGain),
        ]
        let p = customMetadataPrefix
        metadata["\(p)elapsedTime"] = detail.elapsedTime
        metadata["\(p)stravaActivityId"] = detail.id
        if let v = detail.averageHeartrate { metadata["\(p)avgHeartRate"] = v }
        if let v = detail.maxHeartrate { metadata["\(p)maxHeartRate"] = v }
        if let v = detail.averageCadence { metadata["\(p)avgCadence"] = v }
        if let v = detail.averageWatts { metadata["\(p)avgWatts"] = v }
        if let v = detail.maxWatts { metadata["\(p)maxWatts"] = v }
        if let v = detail.weightedAverageWatts { metadata["\(p)weightedAvgWatts"] = v }
        if let v = detail.kilojoules { metadata["\(p)kilojoules"] = v }
        if let v = detail.deviceName { metadata["\(p)deviceName"] = v }
        if let v = detail.workoutType { metadata["\(p)stravaWorkoutType"] = v }

        var hrSamples: [HKQuantitySample] = []
        if let hr = streams.heartrate, let time = streams.time, !hr.data.isEmpty {
            let hrType = HKQuantityType(.heartRate)
            let hrUnit = HKUnit.count().unitDivided(by: .minute())
            let count = min(hr.data.count, time.data.count)
            hrSamples.reserveCapacity(count)
            for i in 0..<count {
                let sampleDate = startDate.addingTimeInterval(TimeInterval(time.data[i]))
                hrSamples.append(HKQuantitySample(
                    type: hrType,
                    quantity: HKQuantity(unit: hrUnit, doubleValue: Double(hr.data[i])),
                    start: sampleDate,
                    end: sampleDate
                ))
            }
        }

        return WorkoutBlueprint(
            activityType: activityType,
            startDate: startDate,
            endDate: endDate,
            duration: duration,
            totalDistance: HKQuantity(unit: .meter(), doubleValue: detail.distance),
            totalEnergyBurned: HKQuantity(unit: .kilocalorie(), doubleValue: detail.calories),
            metadata: metadata,
            heartRateSamples: hrSamples
        )
    }

    func writeWorkout(detail: StravaActivityDetail, streams: StravaStreams) async throws -> HKWorkout {
        let blueprint = try Self.buildBlueprint(detail: detail, streams: streams)

        let config = HKWorkoutConfiguration()
        config.activityType = blueprint.activityType

        let builder = HKWorkoutBuilder(healthStore: healthStore, configuration: config, device: nil)
        try await builder.beginCollection(at: blueprint.startDate)
        try await builder.addMetadata(blueprint.metadata)

        let distanceSample = HKQuantitySample(
            type: Self.distanceQuantityType(for: blueprint.activityType),
            quantity: blueprint.totalDistance,
            start: blueprint.startDate,
            end: blueprint.endDate
        )
        let energySample = HKQuantitySample(
            type: HKQuantityType(.activeEnergyBurned),
            quantity: blueprint.totalEnergyBurned,
            start: blueprint.startDate,
            end: blueprint.endDate
        )
        var samples: [HKSample] = [distanceSample, energySample]
        samples.append(contentsOf: blueprint.heartRateSamples)
        try await builder.addSamples(samples)

        try await builder.endCollection(at: blueprint.endDate)
        guard let workout = try await builder.finishWorkout() else {
            throw WriteWorkoutError.builderReturnedNil
        }
        return workout
    }

    func hasEffortScore(for workout: HKWorkout) async throws -> Bool {
        let relatedPredicate = HKQuery.predicateForWorkoutEffortSamplesRelated(
            workout: workout,
            activity: nil
        )
        let descriptor = HKSampleQueryDescriptor(
            predicates: [
                HKSamplePredicate<HKQuantitySample>.quantitySample(
                    type: effortType,
                    predicate: relatedPredicate
                )
            ],
            sortDescriptors: [],
            limit: 1
        )
        return try await !descriptor.result(for: healthStore).isEmpty
    }

}
