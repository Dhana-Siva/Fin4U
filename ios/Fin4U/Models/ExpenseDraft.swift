import Foundation
import Observation
import SwiftData

struct DraftItem: Identifiable, Equatable {
    var id = UUID()
    var name: String
    var quantity: Int
    var cents: Int
}

/// The editable working copy behind the review screen -- either a freshly
/// scanned receipt or an existing expense being corrected. Nothing touches
/// the database until `save(in:)`.
@Observable
final class ExpenseDraft {
    var merchant: String
    var date: Date
    var currency: String
    var category: ExpenseCategory
    var items: [DraftItem]
    var taxCents: Int
    var tipCents: Int
    var notes: [String]
    var receiptImage: Data?

    /// What the receipt itself printed -- kept only to cross-check the items
    /// as the user edits. Zero means "not shown", and for an already-saved
    /// expense there's nothing left to compare against.
    let printedSubtotalCents: Int
    let printedTotalCents: Int

    /// Set when editing a saved expense, so `save` updates it in place.
    let existing: Expense?

    init(
        merchant: String = "",
        date: Date = Date(),
        currency: String = "USD",
        category: ExpenseCategory = .other,
        items: [DraftItem] = [],
        taxCents: Int = 0,
        tipCents: Int = 0,
        notes: [String] = [],
        receiptImage: Data? = nil,
        printedSubtotalCents: Int = 0,
        printedTotalCents: Int = 0,
        existing: Expense? = nil
    ) {
        self.merchant = merchant
        self.date = date
        self.currency = currency
        self.category = category
        self.items = items
        self.taxCents = taxCents
        self.tipCents = tipCents
        self.notes = notes
        self.receiptImage = receiptImage
        self.printedSubtotalCents = printedSubtotalCents
        self.printedTotalCents = printedTotalCents
        self.existing = existing
    }

    convenience init(parsed: ParsedReceipt, image: Data?) {
        self.init(
            merchant: parsed.merchant,
            date: Self.parseDate(parsed.date) ?? Date(),
            currency: parsed.currency.isEmpty ? "USD" : parsed.currency,
            category: ExpenseCategory(raw: parsed.category),
            items: parsed.items.map { DraftItem(name: $0.name, quantity: max($0.quantity, 1), cents: $0.lineTotalCents) },
            taxCents: parsed.taxCents,
            tipCents: parsed.tipCents,
            notes: parsed.notes,
            receiptImage: image,
            printedSubtotalCents: parsed.subtotalCents,
            printedTotalCents: parsed.totalCents
        )
    }

    convenience init(expense: Expense) {
        self.init(
            merchant: expense.merchant,
            date: expense.date,
            currency: expense.currency,
            category: expense.category,
            items: expense.sortedItems.map { DraftItem(name: $0.name, quantity: $0.quantity, cents: $0.lineTotalCents) },
            taxCents: expense.taxCents,
            tipCents: expense.tipCents,
            receiptImage: expense.receiptImage,
            existing: expense
        )
    }

    // MARK: Derived totals -- always computed from the items, never stored
    // separately, so they can't drift out of sync with what's on screen.

    var subtotalCents: Int { items.reduce(0) { $0 + $1.cents } }
    var totalCents: Int { subtotalCents + taxCents + tipCents }

    var checks: [String] {
        Reconciliation.checks(
            itemsTotal: subtotalCents,
            printedSubtotal: printedSubtotalCents,
            tax: taxCents,
            tip: tipCents,
            printedTotal: printedTotalCents,
            currency: currency
        )
    }

    var canSave: Bool { !items.isEmpty || totalCents != 0 }

    // MARK: Persistence

    func save(in context: ModelContext) {
        let expense = existing ?? Expense(
            merchant: "", date: date, currency: currency, category: category,
            subtotalCents: 0, taxCents: 0, tipCents: 0, totalCents: 0, receiptImage: nil
        )
        if existing == nil { context.insert(expense) }

        let trimmed = merchant.trimmingCharacters(in: .whitespacesAndNewlines)
        expense.merchant = trimmed.isEmpty ? "Receipt" : trimmed
        expense.date = date
        expense.currency = currency
        expense.category = category
        expense.subtotalCents = subtotalCents
        expense.taxCents = taxCents
        expense.tipCents = tipCents
        expense.totalCents = totalCents
        expense.receiptImage = receiptImage

        for old in expense.items { context.delete(old) }
        expense.items = items.enumerated().map { index, item in
            ExpenseItem(name: item.name, quantity: item.quantity, lineTotalCents: item.cents, position: index)
        }
    }

    /// The backend sends YYYY-MM-DD.
    static func parseDate(_ string: String) -> Date? {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.date(from: string)
    }
}
