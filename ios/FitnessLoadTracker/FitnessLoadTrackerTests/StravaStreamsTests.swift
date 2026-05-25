//
//  StravaStreamsTests.swift
//  FitnessLoadTrackerTests
//

import Foundation
import Testing
@testable import FitnessLoadTracker

@Suite("StravaStreams decoding")
struct StravaStreamsTests {
    @Test("decodes 60-minute 1Hz heartrate stream alongside time stream")
    func fullRide() throws {
        let count = 3600
        let hr = (0..<count).map { i in 120 + (i % 50) }
        let times = Array(0..<count)
        let json = makeKeyedJSON(heartrate: hr, time: times).data(using: .utf8)!

        let streams = try StravaClient.decodeStreams(from: json)
        #expect(streams.heartrate?.data.count == count)
        #expect(streams.time?.data.count == count)
        #expect(streams.heartrate?.data.first == 120)
        #expect(streams.heartrate?.data.last == 120 + ((count - 1) % 50))
        #expect(streams.time?.data.first == 0)
        #expect(streams.time?.data.last == count - 1)
        #expect(streams.heartrate?.seriesType == "time")
        #expect(streams.heartrate?.originalSize == count)
        #expect(streams.heartrate?.resolution == "high")
    }

    @Test("tolerates missing heartrate key (phone-only walk, no HR pairing)")
    func noHeartrate() throws {
        let json = """
        {
            "time": {
                "data": [0, 1, 2, 3],
                "series_type": "time",
                "original_size": 4,
                "resolution": "high"
            }
        }
        """.data(using: .utf8)!

        let streams = try StravaClient.decodeStreams(from: json)
        #expect(streams.heartrate == nil)
        #expect(streams.time?.data == [0, 1, 2, 3])
    }

    @Test("tolerates empty data arrays")
    func emptyArrays() throws {
        let json = """
        {
            "heartrate": {
                "data": [],
                "series_type": "time",
                "original_size": 0,
                "resolution": "high"
            },
            "time": {
                "data": [],
                "series_type": "time",
                "original_size": 0,
                "resolution": "high"
            }
        }
        """.data(using: .utf8)!

        let streams = try StravaClient.decodeStreams(from: json)
        #expect(streams.heartrate?.data.isEmpty == true)
        #expect(streams.time?.data.isEmpty == true)
    }

    private func makeKeyedJSON(heartrate: [Int], time: [Int]) -> String {
        let hrCSV = heartrate.map(String.init).joined(separator: ",")
        let timeCSV = time.map(String.init).joined(separator: ",")
        return """
        {
            "heartrate": {
                "data": [\(hrCSV)],
                "series_type": "time",
                "original_size": \(heartrate.count),
                "resolution": "high"
            },
            "time": {
                "data": [\(timeCSV)],
                "series_type": "time",
                "original_size": \(time.count),
                "resolution": "high"
            }
        }
        """
    }
}
