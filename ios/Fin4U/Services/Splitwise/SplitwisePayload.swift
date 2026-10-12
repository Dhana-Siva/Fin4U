import Foundation

/// One person's part of a Splitwise expense, in cents.
struct SplitwiseShare: Equatable {
    var userID: Int
    var paidCents: Int
    var owedCents: Int
}

enum SplitwisePayloadError: LocalizedError, Equatable {
    case sharesDontAddUp
    case nobodyPaid

    var errorDescription: String? {
        switch self {
        case .sharesDontAddUp: "The amounts don't add up to the total, so this wasn't sent to Splitwise."
        case .nobodyPaid: "No one is marked as having paid, so this wasn't sent to Splitwise."
        }
    }
}

/// Builds the form fields for Splitwise's `create_expense` call. Pure, so the
/// money rules can be tested: what each person paid and owes must each add up
/// to the total, to the cent -- otherwise Splitwise rejects it.
enum SplitwisePayload {
    static func fields(
        description: String,
        date: Date,
        currency: String,
        totalCents: Int,
        groupID: Int,
        shares: [SplitwiseShare],
        details: String,
        calendar: Calendar = .current
    ) throws -> [String: String] {
        guard shares.reduce(0, { $0 + $1.paidCents }) == totalCents,
              shares.reduce(0, { $0 + $1.owedCents }) == totalCents else {
            throw shares.contains(where: { $0.paidCents > 0 }) ? SplitwisePayloadError.sharesDontAddUp : .nobodyPaid
        }

        var fields: [String: String] = [
            "cost": Money.plain(totalCents),
            "description": description,
            "details": details,
            "date": isoDate(date, calendar: calendar),
            "currency_code": currency,
            "group_id": String(groupID),  // 0 = not in a group
        ]
        for (index, share) in shares.enumerated() {
            fields["users__\(index)__user_id"] = String(share.userID)
            fields["users__\(index)__paid_share"] = Money.plain(share.paidCents)
            fields["users__\(index)__owed_share"] = Money.plain(share.owedCents)
        }
        return fields
    }

    /// Noon UTC on the receipt's calendar day, so no time zone can shift the
    /// expense to the day before or after.
    static func isoDate(_ date: Date, calendar: Calendar = .current) -> String {
        let day = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02dT12:00:00Z", day.year ?? 1970, day.month ?? 1, day.day ?? 1)
    }

    /// The note on the Splitwise expense: what the receipt was, and each
    /// item with how it was divided, so the other person can see what they're
    /// paying for.
    static func details(
        merchant: String,
        items: [(name: String, cents: Int, shares: [(name: String, cents: Int)])],
        taxCents: Int,
        tipCents: Int,
        currency: String
    ) -> String {
        var lines = ["Receipt from \(merchant) (added with Fin4U)", ""]
        for item in items {
            let parts = item.shares.filter { $0.cents != 0 }
                .map { "\($0.name) \(Money.format($0.cents, currency: currency))" }
                .joined(separator: " / ")
            let name = item.name.isEmpty ? "Item" : item.name
            lines.append("\(name) \(Money.format(item.cents, currency: currency))" + (parts.isEmpty ? "" : "  ->  \(parts)"))
        }
        if taxCents != 0 { lines.append("Tax \(Money.format(taxCents, currency: currency))") }
        if tipCents != 0 { lines.append("Tip / service \(Money.format(tipCents, currency: currency))") }
        lines.append("")
        lines.append("Tax and tip are shared in proportion to each person's items.")
        return lines.joined(separator: "\n")
    }
}
