//
//  StravaStreams.swift
//  FitnessLoadTracker
//

import Foundation

// Response from /api/v3/activities/{id}/streams?key_by_type=true.
// Each requested key becomes a top-level Stream entry, absent when the
// activity has no data for that channel (e.g. phone-only walk with no
// HR pairing → no `heartrate` key in the response).
struct StravaStreams: Decodable, Equatable {
    let heartrate: Stream?
    let time: Stream?

    struct Stream: Decodable, Equatable {
        let data: [Int]
        let seriesType: String
        let originalSize: Int
        let resolution: String

        enum CodingKeys: String, CodingKey {
            case data
            case seriesType = "series_type"
            case originalSize = "original_size"
            case resolution
        }
    }
}
