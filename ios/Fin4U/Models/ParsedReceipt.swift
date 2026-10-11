import Foundation

/// The backend's `/v1/parse-receipt` response. Decoded with
/// `.convertFromSnakeCase`; extra fields the server sends (items_total_cents,
/// reconciles, checks) are ignored -- the app re-runs reconciliation itself.
struct ParsedReceipt: Decodable {
    let isReceipt: Bool
    let merchant: String
    let date: String
    let currency: String
    let category: String
    let items: [ParsedItem]
    let subtotalCents: Int
    let taxCents: Int
    let tipCents: Int
    let totalCents: Int
    let notes: [String]
}

struct ParsedItem: Decodable {
    let name: String
    let quantity: Int
    let lineTotalCents: Int
    /// Optional: older backends don't send it.
    let category: String?
}
