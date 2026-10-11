import Foundation

/// Values injected at build time from Secrets.xcconfig via Info.plist.
enum Config {
    static var backendBaseURL: URL? {
        guard let value = Bundle.main.object(forInfoDictionaryKey: "BackendBaseURL") as? String,
              !value.isEmpty
        else { return nil }
        return URL(string: value)
    }

    static var appKey: String? {
        guard let value = Bundle.main.object(forInfoDictionaryKey: "AppKey") as? String,
              !value.isEmpty
        else { return nil }
        return value
    }

    /// Needs a real hosted page before TestFlight / App Store -- Apple
    /// requires the policy itself (not just in-app text) to disclose the
    /// Anthropic data flow.
    static let privacyPolicyURL = URL(string: "https://dhana-siva.github.io/Fin4U/")!
}
