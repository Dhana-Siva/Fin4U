import Foundation

/// The backend's `/v1/parse-statement` response, decoded with
/// `.convertFromSnakeCase`. Amounts are cents: spending is positive,
/// credits (refunds, payments) are negative.
struct ParsedStatement: Decodable {
    let issuer: String
    let cardLast4: String
    let currency: String
    let periodStart: String
    let periodEnd: String
    let transactions: [StatementTransaction]
    let notes: [String]
}

struct StatementTransaction: Decodable, Equatable {
    let date: String
    let description: String
    let merchant: String
    let amountCents: Int
    let kind: Kind
    let category: String

    enum Kind: String, Decodable {
        case purchase, refund, payment, fee, interest, otherCredit = "other_credit"

        /// Unknown kinds from a newer backend are treated as purchases rather
        /// than failing the whole statement.
        init(from decoder: Decoder) throws {
            let raw = try decoder.singleValueContainer().decode(String.self)
            self = Kind(rawValue: raw) ?? .purchase
        }
    }
}
