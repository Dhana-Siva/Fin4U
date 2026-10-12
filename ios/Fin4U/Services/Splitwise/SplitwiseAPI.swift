import Foundation

enum SplitwiseError: LocalizedError, Equatable {
    case notConnected
    /// The token was refused (revoked, or Splitwise signed it out).
    case unauthorized
    /// Splitwise understood the request but refused it; the messages say why.
    case rejected([String])
    case network
    case unreadableResponse

    var errorDescription: String? {
        switch self {
        case .notConnected: "Splitwise isn't connected. Connect it from your profile."
        case .unauthorized: "Splitwise signed you out. Connect it again from your profile."
        case .rejected(let messages):
            messages.isEmpty ? "Splitwise didn't accept that expense." : "Splitwise said: " + messages.joined(separator: " ")
        case .network: "Couldn't reach Splitwise. Check your connection and try again."
        case .unreadableResponse: "Got an unexpected reply from Splitwise. Try again."
        }
    }
}

/// Talks to Splitwise directly from the phone with the user's own token. The
/// receipt server is not involved after sign-in.
final class SplitwiseAPI {
    static let baseURL = URL(string: "https://secure.splitwise.com/api/v3.0/")!

    private let token: () -> String?
    private let session: URLSession

    init(token: @escaping () -> String?, session: URLSession? = nil) {
        self.token = token
        if let session {
            self.session = session
        } else {
            let configuration = URLSessionConfiguration.ephemeral
            configuration.timeoutIntervalForRequest = 30
            self.session = URLSession(configuration: configuration)
        }
    }

    func currentUser() async throws -> SplitwiseUser {
        try await get("get_current_user", as: SplitwiseCurrentUserResponse.self).user
    }

    func friends() async throws -> [SplitwiseUser] {
        try await get("get_friends", as: SplitwiseFriendsResponse.self).friends
    }

    func groups() async throws -> [SplitwiseGroup] {
        try await get("get_groups", as: SplitwiseGroupsResponse.self).groups
            .filter { $0.id != 0 }  // 0 is Splitwise's catch-all for expenses outside any group
    }

    /// Creates the expense and returns its Splitwise id.
    func createExpense(fields: [String: String]) async throws -> Int {
        var request = try authorizedRequest("create_expense")
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded; charset=utf-8", forHTTPHeaderField: "Content-Type")
        request.httpBody = Self.formBody(fields)
        let data = try await send(request)
        let reply = try decode(SplitwiseCreateExpenseResponse.self, from: data)
        if let messages = reply.errors?.messages, !messages.isEmpty { throw SplitwiseError.rejected(messages) }
        guard let id = reply.expenses?.first?.id else { throw SplitwiseError.unreadableResponse }
        return id
    }

    // MARK: Plumbing

    private func get<T: Decodable>(_ path: String, as type: T.Type) async throws -> T {
        let data = try await send(try authorizedRequest(path))
        return try decode(type, from: data)
    }

    private func authorizedRequest(_ path: String) throws -> URLRequest {
        guard let token = token(), !token.isEmpty else { throw SplitwiseError.notConnected }
        var request = URLRequest(url: Self.baseURL.appendingPathComponent(path))
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        return request
    }

    private func send(_ request: URLRequest) async throws -> Data {
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw SplitwiseError.network
        }
        guard let http = response as? HTTPURLResponse else { throw SplitwiseError.unreadableResponse }
        switch http.statusCode {
        case 200..<300: return data
        case 401, 403: throw SplitwiseError.unauthorized
        case 400..<500:
            // Splitwise explains refusals in `errors`.
            let messages = (try? decode(SplitwiseCreateExpenseResponse.self, from: data))?.errors?.messages ?? []
            throw SplitwiseError.rejected(messages)
        default: throw SplitwiseError.network
        }
    }

    private func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        do { return try decoder.decode(type, from: data) } catch { throw SplitwiseError.unreadableResponse }
    }

    /// x-www-form-urlencoded with strict escaping: only unreserved characters
    /// pass through, so notes with newlines, '&', '+' or accents survive intact.
    static func formBody(_ fields: [String: String]) -> Data {
        let allowed = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")
        func escape(_ text: String) -> String { text.addingPercentEncoding(withAllowedCharacters: allowed) ?? "" }
        let pairs = fields.keys.sorted().map { "\(escape($0))=\(escape(fields[$0] ?? ""))" }
        return Data(pairs.joined(separator: "&").utf8)
    }
}
