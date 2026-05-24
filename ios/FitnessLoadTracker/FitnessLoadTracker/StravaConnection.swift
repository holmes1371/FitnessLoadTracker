//
//  StravaConnection.swift
//  FitnessLoadTracker
//

import Foundation
import Observation

@Observable
final class StravaConnection {
    enum State: Equatable {
        case disconnected
        case connecting
        case connected(athleteName: String)
        case failed(String)
    }

    var state: State

    private let auth = StravaAuth()
    private static let athleteNameKey = "stravaAthleteName"

    init() {
        if Keychain.load() != nil {
            let name = UserDefaults.standard.string(forKey: Self.athleteNameKey) ?? "Strava user"
            self.state = .connected(athleteName: name)
        } else {
            self.state = .disconnected
        }
    }

    func connect() async {
        state = .connecting
        do {
            let athlete = try await auth.authenticate()
            UserDefaults.standard.set(athlete.fullName, forKey: Self.athleteNameKey)
            state = .connected(athleteName: athlete.fullName)
        } catch {
            state = .failed(error.localizedDescription)
        }
    }
}
