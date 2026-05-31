//
//  DuplicateDetectionTests.swift
//  FitnessLoadTrackerTests
//

import Foundation
import HealthKit
import Testing
@testable import FitnessLoadTracker

@Suite("DuplicateDetection")
struct DuplicateDetectionTests {
    private static let base = Date(timeIntervalSince1970: 1_716_220_800)

    private func workout(
        startOffset: TimeInterval = 0,
        duration: TimeInterval = 3600,
        type: HKWorkoutActivityType = .cycling,
        source: String = "Strava",
        distanceMeters: Double? = nil
    ) -> WorkoutForDuplicateCheck {
        WorkoutForDuplicateCheck(
            id: UUID(),
            startDate: Self.base.addingTimeInterval(startOffset),
            duration: duration,
            activityType: type,
            sourceName: source,
            distanceMeters: distanceMeters
        )
    }

    @Test("no workouts yields no clusters")
    func empty() {
        #expect(DuplicateDetection.clusters(in: []).isEmpty)
    }

    @Test("a single workout is not a cluster")
    func singleton() {
        #expect(DuplicateDetection.clusters(in: [workout()]).isEmpty)
    }

    @Test("two matching workouts form one cluster of two")
    func pair() {
        let clusters = DuplicateDetection.clusters(in: [
            workout(source: "Peloton"),
            workout(startOffset: 30, duration: 3640, source: "Strava"),
        ])
        #expect(clusters.count == 1)
        #expect(clusters[0].members.count == 2)
    }

    @Test("different activity type does not cluster")
    func differentType() {
        let clusters = DuplicateDetection.clusters(in: [
            workout(type: .cycling),
            workout(type: .running),
        ])
        #expect(clusters.isEmpty)
    }

    @Test("start beyond tolerance does not cluster")
    func startOutsideTolerance() {
        let clusters = DuplicateDetection.clusters(in: [
            workout(),
            workout(startOffset: 90),
        ])
        #expect(clusters.isEmpty)
    }

    @Test("duration beyond tolerance does not cluster")
    func durationOutsideTolerance() {
        let clusters = DuplicateDetection.clusters(in: [
            workout(duration: 3600),
            workout(duration: 3700),
        ])
        #expect(clusters.isEmpty)
    }

    @Test("three near-identical workouts form one cluster of three")
    func threeWay() {
        let clusters = DuplicateDetection.clusters(in: [
            workout(source: "A"),
            workout(startOffset: 20, source: "B"),
            workout(startOffset: 40, source: "C"),
        ])
        #expect(clusters.count == 1)
        #expect(clusters[0].members.count == 3)
    }

    @Test("differing distance still clusters — distance is not a match key")
    func distanceIgnored() {
        let clusters = DuplicateDetection.clusters(in: [
            workout(distanceMeters: 20000),
            workout(startOffset: 10, distanceMeters: nil),
        ])
        #expect(clusters.count == 1)
        #expect(clusters[0].members.count == 2)
    }

    @Test("two independent pairs form two clusters")
    func twoClusters() {
        let clusters = DuplicateDetection.clusters(in: [
            workout(startOffset: 0),
            workout(startOffset: 20),
            workout(startOffset: 7200),
            workout(startOffset: 7220),
        ])
        #expect(clusters.count == 2)
        #expect(clusters.allSatisfy { $0.members.count == 2 })
    }

    @Test("cluster id is stable regardless of member order")
    func stableId() {
        let a = workout()
        let b = workout(startOffset: 10)
        let c1 = DuplicateDetection.clusters(in: [a, b])
        let c2 = DuplicateDetection.clusters(in: [b, a])
        #expect(c1[0].id == c2[0].id)
    }
}
