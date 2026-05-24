//
//  MatchingTests.swift
//  FitnessLoadTrackerTests
//

import Foundation
import HealthKit
import Testing
@testable import FitnessLoadTracker

@Suite("Matching")
struct MatchingTests {
    private func activity(
        sportType: String = "Ride",
        startDate: Date = .test(),
        elapsedTime: Int = 3600
    ) -> StravaActivity {
        StravaActivity(
            id: 1,
            name: "Test",
            sportType: sportType,
            startDate: startDate,
            elapsedTime: elapsedTime,
            movingTime: elapsedTime,
            sufferScore: 50
        )
    }

    private func candidate(
        startOffset: TimeInterval = 0,
        durationDelta: TimeInterval = 0,
        type: HKWorkoutActivityType = .cycling,
        bundleID: String = ""
    ) -> WorkoutCandidate {
        WorkoutCandidate(
            startDate: Date.test().addingTimeInterval(startOffset),
            duration: 3600 + durationDelta,
            activityType: type,
            bundleID: bundleID
        )
    }

    private let pelotonBundle = "com.Peloton.PelotonApp"
    private let stravaBundle = "com.strava.stravaride"

    @Test("exact match returns matched(index:)")
    func exactMatch() {
        let result = Matching.findMatch(for: activity(), in: [candidate()])
        #expect(result == .matched(index: 0))
    }

    @Test("start time within tolerance still matches")
    func startWithinTolerance() {
        let result = Matching.findMatch(for: activity(), in: [candidate(startOffset: 45)])
        #expect(result == .matched(index: 0))
    }

    @Test("start time outside tolerance does not match")
    func startOutsideTolerance() {
        let result = Matching.findMatch(for: activity(), in: [candidate(startOffset: 90)])
        #expect(result == .noMatch)
    }

    @Test("duration within tolerance still matches")
    func durationWithinTolerance() {
        let result = Matching.findMatch(for: activity(), in: [candidate(durationDelta: 45)])
        #expect(result == .matched(index: 0))
    }

    @Test("duration outside tolerance does not match")
    func durationOutsideTolerance() {
        let result = Matching.findMatch(for: activity(), in: [candidate(durationDelta: 120)])
        #expect(result == .noMatch)
    }

    @Test("wrong activity type does not match")
    func wrongType() {
        let result = Matching.findMatch(for: activity(sportType: "Ride"), in: [candidate(type: .running)])
        #expect(result == .noMatch)
    }

    @Test("two qualifying candidates returns multipleMatches")
    func multipleMatches() {
        let result = Matching.findMatch(
            for: activity(),
            in: [candidate(), candidate(startOffset: 30)]
        )
        #expect(result == .multipleMatches)
    }

    @Test("Peloton + Strava pair resolves to the Peloton candidate")
    func pelotonStravaTiebreaker() {
        let result = Matching.findMatch(
            for: activity(),
            in: [
                candidate(bundleID: pelotonBundle),
                candidate(startOffset: 30, bundleID: stravaBundle),
            ]
        )
        #expect(result == .matched(index: 0))
    }

    @Test("Strava + Peloton (reverse order) still resolves to Peloton")
    func pelotonStravaTiebreakerReversed() {
        let result = Matching.findMatch(
            for: activity(),
            in: [
                candidate(bundleID: stravaBundle),
                candidate(startOffset: 30, bundleID: pelotonBundle),
            ]
        )
        #expect(result == .matched(index: 1))
    }

    @Test("two Peloton-sourced candidates still returns multipleMatches")
    func twoPelotonStaysMultiple() {
        let result = Matching.findMatch(
            for: activity(),
            in: [
                candidate(bundleID: pelotonBundle),
                candidate(startOffset: 30, bundleID: pelotonBundle),
            ]
        )
        #expect(result == .multipleMatches)
    }

    @Test("two Strava-sourced candidates still returns multipleMatches")
    func twoStravaStaysMultiple() {
        let result = Matching.findMatch(
            for: activity(),
            in: [
                candidate(bundleID: stravaBundle),
                candidate(startOffset: 30, bundleID: stravaBundle),
            ]
        )
        #expect(result == .multipleMatches)
    }

    @Test("Peloton + Strava + third source still returns multipleMatches")
    func threeWayWithThirdSourceStaysMultiple() {
        let result = Matching.findMatch(
            for: activity(),
            in: [
                candidate(bundleID: pelotonBundle),
                candidate(startOffset: 20, bundleID: stravaBundle),
                candidate(startOffset: 40, bundleID: "com.example.thirdparty"),
            ]
        )
        #expect(result == .multipleMatches)
    }

    @Test("unmapped sport type returns noMatch")
    func unmappedSportType() {
        let result = Matching.findMatch(
            for: activity(sportType: "Pickleball"),
            in: [candidate()]
        )
        #expect(result == .noMatch)
    }

    @Test(
        "Strava sport types map to expected HKWorkoutActivityType",
        arguments: [
            ("Ride", HKWorkoutActivityType.cycling),
            ("VirtualRide", .cycling),
            ("MountainBikeRide", .cycling),
            ("EBikeRide", .cycling),
            ("Run", .running),
            ("TrailRun", .running),
            ("VirtualRun", .running),
            ("Walk", .walking),
            ("Hike", .hiking),
            ("Swim", .swimming),
        ]
    )
    func sportTypeMapping(_ stravaType: String, _ expected: HKWorkoutActivityType) {
        #expect(Matching.hkActivityType(forStravaSportType: stravaType) == expected)
    }

    @Test("unmapped sport types return nil from the type mapper")
    func unmappedMapping() {
        #expect(Matching.hkActivityType(forStravaSportType: "Pickleball") == nil)
        #expect(Matching.hkActivityType(forStravaSportType: "Yoga") == nil)
        #expect(Matching.hkActivityType(forStravaSportType: "") == nil)
    }
}

private extension Date {
    static func test() -> Date {
        Date(timeIntervalSince1970: 1_716_220_800)
    }
}
