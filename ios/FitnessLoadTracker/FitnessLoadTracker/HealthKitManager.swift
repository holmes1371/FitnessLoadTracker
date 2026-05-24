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
            let sample = HKQuantitySample(
                type: effortType,
                quantity: HKQuantity(unit: .appleEffortScore(), doubleValue: 7),
                start: workout.endDate,
                end: workout.endDate
            )
            try await healthStore.save(sample)
            try await healthStore.relateWorkoutEffortSample(sample, with: workout, activity: nil)
            let when = workout.endDate.formatted(date: .abbreviated, time: .shortened)
            status = .success("Set effort 7 on workout ending \(when).")
        } catch {
            status = .failure(error.localizedDescription)
        }
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
