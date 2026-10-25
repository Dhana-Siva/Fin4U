import Foundation

enum ReceiptAPIError: LocalizedError {
    case notConfigured
    case network
    case server(String)
    case unreadableResponse

    var errorDescription: String? {
        switch self {
        case .notConfigured:
            return "This build isn't set up to reach the receipt reader."
        case .network:
            return "Couldn't reach the receipt reader. Check your connection and try again."
        case .server(let message):
            return message
        case .unreadableResponse:
            return "Got an unexpected response from the receipt reader. Try again."
        }
    }
}

/// Sends a receipt photo to the backend and returns the parsed items.
/// The backend holds the Anthropic key; this app only ever talks to it.
final class ReceiptAPI {
    static let shared = ReceiptAPI()

    private let session: URLSession

    init(session: URLSession? = nil) {
        if let session {
            self.session = session
        } else {
            // Ephemeral: no cookies, and no on-disk URL cache of receipt data.
            let configuration = URLSessionConfiguration.ephemeral
            configuration.timeoutIntervalForRequest = 120  // the model can take a while on long receipts
            self.session = URLSession(configuration: configuration)
        }
    }

    private struct Part {
        let field: String
        let filename: String
        let contentType: String
        let data: Data
    }

    func parse(jpeg: Data) async throws -> ParsedReceipt {
        try await post(
            "v1/parse-receipt",
            parts: [Part(field: "image", filename: "receipt.jpg", contentType: "image/jpeg", data: jpeg)]
        )
    }

    /// A card statement as the bank's PDF download.
    func parseStatement(pdf: Data) async throws -> ParsedStatement {
        try await post(
            "v1/parse-statement",
            parts: [Part(field: "pdf", filename: "statement.pdf", contentType: "application/pdf", data: pdf)],
            timeout: 300
        )
    }

    /// A card statement as photos of its pages, in order.
    func parseStatement(pages: [Data]) async throws -> ParsedStatement {
        try await post(
            "v1/parse-statement",
            parts: pages.enumerated().map {
                Part(field: "pages", filename: "page\($0.offset + 1).jpg", contentType: "image/jpeg", data: $0.element)
            },
            timeout: 300
        )
    }

    /// Statements can take a minute or two to read (the backend only answers
    /// once the whole statement is done), hence the longer per-call timeout.
    private func post<Response: Decodable>(_ path: String, parts: [Part], timeout: TimeInterval? = nil) async throws -> Response {
        guard let baseURL = Config.backendBaseURL, let appKey = Config.appKey else {
            throw ReceiptAPIError.notConfigured
        }

        let boundary = "Boundary-\(UUID().uuidString)"
        var request = URLRequest(url: baseURL.appendingPathComponent(path))
        request.httpMethod = "POST"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.setValue(appKey, forHTTPHeaderField: "X-App-Key")
        if let timeout { request.timeoutInterval = timeout }

        var body = Data()
        for part in parts {
            body.append("--\(boundary)\r\n")
            body.append("Content-Disposition: form-data; name=\"\(part.field)\"; filename=\"\(part.filename)\"\r\n")
            body.append("Content-Type: \(part.contentType)\r\n\r\n")
            body.append(part.data)
            body.append("\r\n")
        }
        body.append("--\(boundary)--\r\n")

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.upload(for: request, from: body)
        } catch is CancellationError {
            throw CancellationError()
        } catch let error as URLError where error.code == .cancelled {
            throw CancellationError()
        } catch {
            throw ReceiptAPIError.network
        }

        guard let http = response as? HTTPURLResponse else { throw ReceiptAPIError.unreadableResponse }

        guard http.statusCode == 200 else {
            throw ReceiptAPIError.server(Self.errorMessage(status: http.statusCode, data: data))
        }

        do {
            let decoder = JSONDecoder()
            decoder.keyDecodingStrategy = .convertFromSnakeCase
            return try decoder.decode(Response.self, from: data)
        } catch {
            throw ReceiptAPIError.unreadableResponse
        }
    }

    /// The backend's errors are `{"detail": "<message meant for the user>"}`.
    static func errorMessage(status: Int, data: Data) -> String {
        if status == 401 {
            return "This build isn't set up to reach the receipt reader."
        }
        if let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let detail = object["detail"] as? String {
            return detail
        }
        return "The receipt reader had a problem (error \(status)). Try again."
    }
}

private extension Data {
    mutating func append(_ string: String) {
        append(Data(string.utf8))
    }
}
