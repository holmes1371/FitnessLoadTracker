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
            try await healthStore.requestAuthorization(
                toShare: [effortType],
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

    func writeEffort(_ value: Double, on workout: HKWorkout) async throws {
        let sample = HKQuantitySample(
            type: effortType,
            quantity: HKQuantity(unit: .appleEffortScore(), doubleValue: value),
            start: workout.endDate,
            end: workout.endDate
        )
        try await healthStore.save(sample)
        try await healthStore.relateWorkoutEffortSample(sample, with: workout, activity: nil)
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
