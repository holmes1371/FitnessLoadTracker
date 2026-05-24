//
//  StravaAuth.swift
//  FitnessLoadTracker
//

import Foundation
import AuthenticationServices
import UIKit

@MainActor
final class StravaAuth {
    enum AuthError: LocalizedError {
        case userCancelled
        case missingCode
        case httpError(Int)
        case decodingError

        var errorDescription: String? {
            switch self {
            case .userCancelled: return "Authorization cancelled."
            case .missingCode: return "Authorization code missing in callback."
            case .httpError(let code): return "Strava returned HTTP \(code)."
            case .decodingError: return "Couldn't decode Strava token response."
            }
        }
    }

    struct Athlete: Decodable {
        let firstname: String
        let lastname: String
        var fullName: String { "\(firstname) \(lastname)".trimmingCharacters(in: .whitespaces) }
    }

    private struct TokenResponse: Decodable {
        let access_token: String
        let refresh_token: String
        let expires_at: Int
        let athlete: Athlete
    }

    private static let authorizeURL = URL(string: "https://www.strava.com/oauth/authorize")!
    private static let tokenURL = URL(string: "https://www.strava.com/oauth/token")!
    private static let callbackScheme = "fitnessloadtracker"
    private static let redirectURI = "fitnessloadtracker://fitnessloadtracker/oauth-callback"
    private static let scope = "activity:read_all"

    func authenticate() async throws -> Athlete {
        let code = try await fetchAuthorizationCode()
        let tokens = try await exchangeCodeForTokens(code)
        try Keychain.save(tokens.refresh_token)
        return tokens.athlete
    }

    private func fetchAuthorizationCode() async throws -> String {
        var components = URLComponents(url: Self.authorizeURL, resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "client_id", value: Secrets.stravaClientId),
            URLQueryItem(name: "redirect_uri", value: Self.redirectURI),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "approval_prompt", value: "auto"),
            URLQueryItem(name: "scope", value: Self.scope),
        ]
        let authURL = components.url!

        let callbackURL: URL = try await withCheckedThrowingContinuation { continuation in
            let session = ASWebAuthenticationSession(
                url: authURL,
                callbackURLScheme: Self.callbackScheme
            ) { callback, error in
                if let error {
                    let nsError = error as NSError
                    if nsError.domain == ASWebAuthenticationSessionError.errorDomain,
                       nsError.code == ASWebAuthenticationSessionError.canceledLogin.rawValue {
                        continuation.resume(throwing: AuthError.userCancelled)
                    } else {
                        continuation.resume(throwing: error)
                    }
                    return
                }
                guard let callback else {
                    continuation.resume(throwing: AuthError.missingCode)
                    return
                }
                continuation.resume(returning: callback)
            }
            session.presentationContextProvider = AuthPresentationProvider.shared
            session.prefersEphemeralWebBrowserSession = false
            session.start()
        }

        guard let callbackComponents = URLComponents(url: callbackURL, resolvingAgainstBaseURL: false),
              let code = callbackComponents.queryItems?.first(where: { $0.name == "code" })?.value,
              !code.isEmpty else {
            throw AuthError.missingCode
        }
        return code
    }

    private func exchangeCodeForTokens(_ code: String) async throws -> TokenResponse {
        var request = URLRequest(url: Self.tokenURL)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        let body = [
            "client_id=\(Secrets.stravaClientId)",
            "client_secret=\(Secrets.stravaClientSecret)",
            "code=\(code)",
            "grant_type=authorization_code",
        ].joined(separator: "&")
        request.httpBody = Data(body.utf8)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw AuthError.httpError(0)
        }
        guard (200...299).contains(http.statusCode) else {
            throw AuthError.httpError(http.statusCode)
        }
        do {
            return try JSONDecoder().decode(TokenResponse.self, from: data)
        } catch {
            throw AuthError.decodingError
        }
    }
}

final class AuthPresentationProvider: NSObject, ASWebAuthenticationPresentationContextProviding {
    static let shared = AuthPresentationProvider()

    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        let scenes = UIApplication.shared.connectedScenes
        for scene in scenes {
            if let windowScene = scene as? UIWindowScene,
               let keyWindow = windowScene.windows.first(where: { $0.isKeyWindow }) {
                return keyWindow
            }
        }
        return ASPresentationAnchor()
    }
}
