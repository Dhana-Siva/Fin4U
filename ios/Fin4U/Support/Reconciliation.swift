import Foundation

/// Cross-checks the numbers printed on a receipt against the items we
/// extracted, so a misread price is flagged instead of silently saved.
/// Mirrors `reconcile()` in the backend; kept client-side too because the
/// check has to re-run live as the user corrects items.
enum Reconciliation {
    /// An empty result means everything agrees. Pass 0 for a printed value
    /// the receipt didn't show.
    static func checks(
        itemsTotal: Int,
        printedSubtotal: Int,
        tax: Int,
        tip: Int,
        printedTotal: Int,
        currency: String
    ) -> [String] {
        var problems: [String] = []

        if printedSubtotal > 0, itemsTotal != printedSubtotal {
            problems.append(
                "The items add up to \(Money.format(itemsTotal, currency: currency)) but the receipt's subtotal is \(Money.format(printedSubtotal, currency: currency))."
            )
        }

        // Without a printed subtotal, fall back to the items themselves.
        let base = printedSubtotal > 0 ? printedSubtotal : itemsTotal
        let expectedTotal = base + tax + tip
        if printedTotal > 0, expectedTotal != printedTotal {
            problems.append(
                "Subtotal + tax + tip is \(Money.format(expectedTotal, currency: currency)) but the receipt's total is \(Money.format(printedTotal, currency: currency))."
            )
        }
        return problems
    }
}
