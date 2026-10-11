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

    func parse(jpeg: Data) async throws -> ParsedReceipt {
        guard let baseURL = Config.backendBaseURL, let appKey = Config.appKey else {
            throw ReceiptAPIError.notConfigured
        }

        let boundary = "Boundary-\(UUID().uuidString)"
        var request = URLRequest(url: baseURL.appendingPathComponent("v1/parse-receipt"))
        request.httpMethod = "POST"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.setValue(appKey, forHTTPHeaderField: "X-App-Key")

        var body = Data()
        body.append("--\(boundary)\r\n")
        body.append("Content-Disposition: form-data; name=\"image\"; filename=\"receipt.jpg\"\r\n")
        body.append("Content-Type: image/jpeg\r\n\r\n")
        body.append(jpeg)
        body.append("\r\n--\(boundary)--\r\n")

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
            return try decoder.decode(ParsedReceipt.self, from: data)
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
