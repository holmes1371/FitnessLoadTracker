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
    ]

    static let readTypes: Set<HKObjectType> = [
        HKQuantityType(.workoutEffortScore),
        HKWorkoutType.workoutType(),
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

    enum WriteWorkoutError: LocalizedError {
        case unmappedSportType(String)

        var errorDescription: String? {
            switch self {
            case .unmappedSportType(let s):
                return "No HKWorkoutActivityType mapping for Strava sport type '\(s)'."
            }
        }
    }

    struct WorkoutBuild {
        let workout: HKWorkout
        let heartRateSamples: [HKQuantitySample]
    }

    static let customMetadataPrefix = "com.holmes.fitnessloadtracker."

    // Pure constructor — separated from save() so tests can assert on the
    // built HKWorkout + samples without going through a real HKHealthStore.
    // The HKWorkout init below is deprecated in favor of HKWorkoutBuilder;
    // the builder requires a real HKHealthStore at construction which kills
    // this test architecture. Migration tracked in #22.
    static func buildWorkoutData(detail: StravaActivityDetail, streams: StravaStreams) throws -> WorkoutBuild {
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

        let workout = HKWorkout(
            activityType: activityType,
            start: startDate,
            end: endDate,
            duration: duration,
            totalEnergyBurned: HKQuantity(unit: .kilocalorie(), doubleValue: detail.calories),
            totalDistance: HKQuantity(unit: .meter(), doubleValue: detail.distance),
            metadata: metadata
        )

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

        return WorkoutBuild(workout: workout, heartRateSamples: hrSamples)
    }

    func writeWorkout(detail: StravaActivityDetail, streams: StravaStreams) async throws -> HKWorkout {
        let build = try Self.buildWorkoutData(detail: detail, streams: streams)
        try await healthStore.save(build.workout)
        if !build.heartRateSamples.isEmpty {
            try await healthStore.save(build.heartRateSamples)
        }
        return build.workout
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
