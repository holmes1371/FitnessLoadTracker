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

    func requestAuthorization() async {
        do {
            // workoutType is in `toShare` so the POC probe can call
            // healthStore.delete(_:) on workouts authored by other apps.
            try await healthStore.requestAuthorization(
                toShare: [effortType, workoutType],
                read: [effortType, workoutType]
            )
        } catch {
            status = .failure("Authorization error: \(error.localizedDescription)")
        }
    }

    func setEffortSevenOnMostRecentWorkout() async {
        status = .working
        do {
            guard let workout = try await mostRecentWorkout() else {
                status = .failure("No workouts found in HealthKit.")
                return
            }
            try await writeEffort(7, on: workout)
            let when = workout.endDate.formatted(date: .abbreviated, time: .shortened)
            status = .success("Set effort 7 on workout ending \(when).")
        } catch {
            status = .failure(error.localizedDescription)
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

    struct ProbeRow: Identifiable {
        let workout: HKWorkout
        let sourceName: String
        let bundleID: String
        var id: UUID { workout.uuid }
    }

    func recentWorkoutsWithSource(days: Int) async throws -> [ProbeRow] {
        let end = Date()
        let start = Calendar.current.date(byAdding: .day, value: -days, to: end) ?? end
        let workouts = try await workouts(in: start...end)
        return workouts.map { workout in
            let src = workout.sourceRevision.source
            return ProbeRow(workout: workout, sourceName: src.name, bundleID: src.bundleIdentifier)
        }
    }

    func deleteWorkout(_ workout: HKWorkout) async throws {
        try await healthStore.delete([workout])
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

    private func mostRecentWorkout() async throws -> HKWorkout? {
        let descriptor = HKSampleQueryDescriptor(
            predicates: [HKSamplePredicate<HKWorkout>.workout()],
            sortDescriptors: [SortDescriptor(\.endDate, order: .reverse)],
            limit: 1
        )
        return try await descriptor.result(for: healthStore).first
    }
}
