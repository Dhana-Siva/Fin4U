import AuthenticationServices
import Foundation
import Observation
import Security
import UIKit

/// What came back from the sign-in web sheet.
enum SplitwiseCallback: Equatable {
    case handoff(String)
    case failed(String)
}

enum SplitwiseSignIn {
    /// A random, URL-safe value that ties the sign-in's return trip to the
    /// request that started it.
    static func newState() -> String {
        var bytes = [UInt8](repeating: 0, count: 24)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        return Data(bytes).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    /// Reads `fin4u://splitwise?handoff=...&state=...` (or `?error=...`).
    /// A mismatched state is rejected: it didn't come from our request.
    static func parse(callback url: URL, expectedState: String) -> SplitwiseCallback {
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        func value(_ name: String) -> String? { items.first { $0.name == name }?.value }
        guard value("state") == expectedState else { return .failed("state_mismatch") }
        if let error = value("error"), !error.isEmpty { return .failed(error) }
        if let handoff = value("handoff"), !handoff.isEmpty { return .handoff(handoff) }
        return .failed("no_handoff")
    }

    static func message(forFailure code: String) -> String {
        switch code {
        case "access_denied": "Splitwise sign-in was cancelled."
        case "not_configured": "Splitwise isn't set up on the Fin4U server yet."
        case "busy": "Splitwise sign-in is busy. Try again in a moment."
        default: "Couldn't connect to Splitwise. Try again."
        }
    }
}

/// The Splitwise connection: signs in through the Fin4U server (which holds
/// the client secret), keeps the resulting token in the Keychain, and exposes
/// the connected account.
@MainActor
@Observable
final class SplitwiseSession: NSObject, ASWebAuthenticationPresentationContextProviding {
    static let keychainService = "com.dhana.fin4u.splitwise"
    static let keychainAccount = "access-token"

    private(set) var user: SplitwiseUser?
    private(set) var isWorking = false
    var errorMessage: String?

    @ObservationIgnored private var authSession: ASWebAuthenticationSession?
    @ObservationIgnored private(set) lazy var api = SplitwiseAPI(token: { Self.storedToken })

    static var storedToken: String? {
        Keychain.read(service: keychainService, account: keychainAccount)
    }

    var isConnected: Bool { Self.storedToken != nil }

    /// On launch (or when a screen needs it): confirm the stored token still
    /// works and fetch whose account it is.
    func refresh() async {
        guard isConnected else { user = nil; return }
        do {
            user = try await api.currentUser()
        } catch SplitwiseError.unauthorized {
            disconnect()
        } catch {
            // Offline or a hiccup: keep the connection, just don't know the name yet.
        }
    }

    func disconnect() {
        Keychain.delete(service: Self.keychainService, account: Self.keychainAccount)
        user = nil
    }

    func connect() async {
        guard let base = Config.backendBaseURL, Config.appKey != nil else {
            errorMessage = "This build isn't set up to reach Splitwise."
            return
        }
        errorMessage = nil
        isWorking = true
        defer { isWorking = false }

        let state = SplitwiseSignIn.newState()
        var components = URLComponents(url: base.appendingPathComponent("splitwise/authorize"), resolvingAgainstBaseURL: false)
        components?.queryItems = [URLQueryItem(name: "state", value: state)]
        guard let startURL = components?.url else { return }

        do {
            let callback = try await runWebSheet(startURL)
            switch SplitwiseSignIn.parse(callback: callback, expectedState: state) {
            case .failed(let code):
                errorMessage = SplitwiseSignIn.message(forFailure: code)
            case .handoff(let handoff):
                let token = try await collectToken(handoff: handoff, base: base)
                guard Keychain.save(token, service: Self.keychainService, account: Self.keychainAccount) else {
                    errorMessage = "Couldn't save the Splitwise connection on this phone."
                    return
                }
                await refresh()
            }
        } catch let error as ASWebAuthenticationSessionError where error.code == .canceledLogin {
            // Closed the sheet: not an error worth showing.
        } catch {
            errorMessage = "Couldn't connect to Splitwise. Try again."
        }
    }

    private func runWebSheet(_ url: URL) async throws -> URL {
        try await withCheckedThrowingContinuation { continuation in
            let session = ASWebAuthenticationSession(url: url, callbackURLScheme: "fin4u") { callbackURL, error in
                if let callbackURL { continuation.resume(returning: callbackURL) }
                else { continuation.resume(throwing: error ?? SplitwiseError.unreadableResponse) }
            }
            session.presentationContextProvider = self
            authSession = session
            session.start()
        }
    }

    /// Trades the one-time handoff code for the token (the server forgets it
    /// as soon as it's collected).
    private func collectToken(handoff: String, base: URL) async throws -> String {
        guard let appKey = Config.appKey else { throw SplitwiseError.notConnected }
        var request = URLRequest(url: base.appendingPathComponent("splitwise/token"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(appKey, forHTTPHeaderField: "X-App-Key")
        request.httpBody = try JSONEncoder().encode(["handoff": handoff])
        let (data, response) = try await URLSession(configuration: .ephemeral).data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200,
              let reply = try? JSONDecoder().decode([String: String].self, from: data),
              let token = reply["access_token"] else { throw SplitwiseError.unreadableResponse }
        return token
    }

    nonisolated func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        MainActor.assumeIsolated {
            UIApplication.shared.connectedScenes
                .compactMap { $0 as? UIWindowScene }
                .flatMap(\.windows)
                .first { $0.isKeyWindow } ?? ASPresentationAnchor()
        }
    }
}
