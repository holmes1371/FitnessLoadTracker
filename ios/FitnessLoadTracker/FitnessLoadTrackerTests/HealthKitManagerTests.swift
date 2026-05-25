//
//  HealthKitManagerTests.swift
//  FitnessLoadTrackerTests
//

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
