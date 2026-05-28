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
        // Needed by the indoor-ride distance enrichment's native-distance check
        // (#37): without read access HealthKit returns nil statistics, so an
        // outdoor ride that already carries distance would look empty and get a
        // redundant proxy, double-counting it.
        HKQuantityType(.distanceCycling),
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

    // Whether the matched workout already carries its own cycling distance
    // (an outdoor ride from a GPS source). Peloton/indoor rides have none, so
    // nil/zero statistics is the signal to enrich (#37).
    func workoutHasNativeCyclingDistance(_ workout: HKWorkout) -> Bool {
        guard let sum = workout.statistics(for: HKQuantityType(.distanceCycling))?.sumQuantity() else {
            return false
        }
        return sum.doubleValue(for: .meter()) > 0
    }

    // Metadata flag marking a workout we synthesized purely to carry an indoor
    // ride's distance (#37) — distinct from a full app-authored workout. Drives
    // dedup and the exclusion of these proxies from match candidates.
    static let distanceProxyMetadataKey = "\(customMetadataPrefix)distanceProxy"

    // 1s keeps the proxy's contribution to cycling TIME and Apple's Exercise
    // minutes negligible. It also sits far from the ride's real duration, but we
    // don't lean on that — Matching excludes proxies explicitly (see
    // SyncOrchestrator.process) so a short ride can't collide.
    static let distanceProxyDuration: TimeInterval = 1

    func isDistanceProxy(_ workout: HKWorkout) -> Bool {
        (workout.metadata?[Self.distanceProxyMetadataKey] as? Bool) == true
    }

    // True if a prior sync already created the distance proxy for this ride —
    // the idempotency guard. Scoped to our own source and matched on the Strava
    // activity id so nothing else counts.
    func hasDistanceProxyWorkout(stravaActivityId: Int64, in range: ClosedRange<Date>) async throws -> Bool {
        let datePredicate = HKQuery.predicateForSamples(withStart: range.lowerBound, end: range.upperBound)
        let sourcePredicate = HKQuery.predicateForObjects(from: .default())
        let predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [datePredicate, sourcePredicate])
        let descriptor = HKSampleQueryDescriptor(
            predicates: [HKSamplePredicate<HKWorkout>.workout(predicate)],
            sortDescriptors: []
        )
        let workouts = try await descriptor.result(for: healthStore)
        return workouts.contains {
            isDistanceProxy($0)
                && ($0.metadata?["\(Self.customMetadataPrefix)stravaActivityId"] as? Int64) == stravaActivityId
        }
    }

    // Author a near-zero-duration cycling workout carrying the indoor ride's
    // distance. We can't add distance onto the source-app workout (HK only lets
    // an app modify samples it authored, #12), so this sibling workout is how
    // the distance reaches the per-workout cycling rollup. Stamped with the
    // Strava id + proxy flag.
    func writeDistanceProxyWorkout(meters: Double, start: Date, stravaActivityId: Int64) async throws {
        let end = start.addingTimeInterval(Self.distanceProxyDuration)
        let config = HKWorkoutConfiguration()
        config.activityType = .cycling
        let builder = HKWorkoutBuilder(healthStore: healthStore, configuration: config, device: nil)
        try await builder.beginCollection(at: start)
        try await builder.addMetadata([
            "\(Self.customMetadataPrefix)stravaActivityId": stravaActivityId,
            Self.distanceProxyMetadataKey: true,
        ])
        let sample = HKQuantitySample(
            type: HKQuantityType(.distanceCycling),
            quantity: HKQuantity(unit: .meter(), doubleValue: meters),
            start: start,
            end: end
        )
        try await builder.addSamples([sample])
        try await builder.endCollection(at: end)
        guard try await builder.finishWorkout() != nil else {
            throw WriteWorkoutError.builderReturnedNil
        }
    }

    enum WriteWorkoutError: LocalizedError {
        case unmappedSportType(String)
        case builderReturnedNil

        var errorDescription: String? {
            switch self {
            case .unmappedSportType(let s):
                return "No HKWorkoutActivityType mapping for Strava sport type '\(s)'."
            case .builderReturnedNil:
                return "HKWorkoutBuilder.finishWorkout returned nil — workout not saved."
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
