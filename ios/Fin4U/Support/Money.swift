import Foundation

/// Money is integer cents everywhere. Floating-point dollars drift
/// (0.1 + 0.2 != 0.3), and shares that don't add up exactly are the one
/// thing a splitting app can't get wrong.
enum Money {
    /// Parses what a person types into an amount field. Accepts "12", "12.5",
    /// "12.50", ".99", "-1.50" and thousands commas. Returns nil for anything
    /// else (including an empty string -- callers decide what empty means).
    static func parseCents(_ text: String) -> Int? {
        let cleaned = text
            .trimmingCharacters(in: .whitespaces)
            .replacingOccurrences(of: ",", with: "")
        // Validate the whole string up front: Decimal(string:) can accept a
        // numeric prefix of garbage (e.g. "12.3.4" -> 12.3), which would
        // silently turn a typo into a wrong amount.
        guard cleaned.range(of: #"^-?(\d+\.?\d*|\.\d+)$"#, options: .regularExpression) != nil,
              let value = Decimal(string: cleaned, locale: Locale(identifier: "en_US_POSIX"))
        else { return nil }

        var scaled = value * 100
        var rounded = Decimal()
        NSDecimalRound(&rounded, &scaled, 0, .plain)
        return NSDecimalNumber(decimal: rounded).intValue
    }

    /// "12.34" -- the editable form, no currency symbol or grouping.
    static func plain(_ cents: Int) -> String {
        let sign = cents < 0 ? "-" : ""
        let absolute = abs(cents)
        return "\(sign)\(absolute / 100).\(String(format: "%02d", absolute % 100))"
    }

    /// "$12.34" -- locale-aware display for the given ISO currency code.
    static func format(_ cents: Int, currency: String) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = currency.isEmpty ? "USD" : currency
        let amount = NSDecimalNumber(value: cents).dividing(by: 100)
        return formatter.string(from: amount) ?? plain(cents)
    }
}
