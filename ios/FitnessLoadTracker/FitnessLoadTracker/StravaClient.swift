//
//  StravaClient.swift
//  FitnessLoadTracker
//

import Foundation

struct StravaClient {
    enum ClientError: LocalizedError {
        case httpError(Int)
        case decodingError(String)

        var errorDescription: String? {
            switch self {
            case .httpError(let code): return "Strava returned HTTP \(code)."
            case .decodingError(let detail): return "Couldn't decode Strava response: \(detail)"
            }
        }
    }

    struct TokenRefresh: Decodable {
        let accessToken: String
        let refreshToken: String
        let expiresAt: Int

        enum CodingKeys: String, CodingKey {
            case accessToken = "access_token"
            case refreshToken = "refresh_token"
            case expiresAt = "expires_at"
        }
    }

    private let session: URLSession
    private static let tokenURL = URL(string: "https://www.strava.com/oauth/token")!
    private static let activitiesURL = URL(string: "https://www.strava.com/api/v3/athlete/activities")!
    private static let activityDetailBaseURL = URL(string: "https://www.strava.com/api/v3/activities/")!

    init(session: URLSession = .shared) {
        self.session = session
    }

    func refreshAccessToken(refreshToken: String) async throws -> TokenRefresh {
        var request = URLRequest(url: Self.tokenURL)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        let body = [
            "client_id=\(Secrets.stravaClientId)",
            "client_secret=\(Secrets.stravaClientSecret)",
            "grant_type=refresh_token",
            "refresh_token=\(refreshToken)",
        ].joined(separator: "&")
        request.httpBody = Data(body.utf8)

        let (data, response) = try await session.data(for: request)
        try Self.ensureSuccess(response)
        do {
            return try JSONDecoder().decode(TokenRefresh.self, from: data)
        } catch {
            throw ClientError.decodingError(String(describing: error))
        }
    }

    func fetchActivities(accessToken: String, after: Date) async throws -> [StravaActivity] {
        var components = URLComponents(url: Self.activitiesURL, resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "after", value: String(Int(after.timeIntervalSince1970))),
            URLQueryItem(name: "per_page", value: "30"),
        ]
        var request = URLRequest(url: components.url!)
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await session.data(for: request)
        try Self.ensureSuccess(response)
        return try Self.decodeActivities(from: data)
    }

    static func decodeActivities(from data: Data) throws -> [StravaActivity] {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        do {
            return try decoder.decode([StravaActivity].self, from: data)
        } catch {
            throw ClientError.decodingError(String(describing: error))
        }
    }

    func fetchActivityDetail(accessToken: String, id: Int64) async throws -> StravaActivityDetail {
        let url = Self.activityDetailBaseURL.appendingPathComponent(String(id))
        var request = URLRequest(url: url)
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await session.data(for: request)
        try Self.ensureSuccess(response)
        return try Self.decodeActivityDetail(from: data)
    }

    static func decodeActivityDetail(from data: Data) throws -> StravaActivityDetail {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        do {
            return try decoder.decode(StravaActivityDetail.self, from: data)
        } catch {
            throw ClientError.decodingError(String(describing: error))
        }
    }

    private static func ensureSuccess(_ response: URLResponse) throws {
        guard let http = response as? HTTPURLResponse else {
            throw ClientError.httpError(0)
        }
        guard (200...299).contains(http.statusCode) else {
            throw ClientError.httpError(http.statusCode)
        }
    }
}
