import Foundation
import Observation
import SwiftData

struct DraftItem: Identifiable, Equatable {
    var id = UUID()
    var name: String
    var quantity: Int
    var cents: Int
    var category: ExpenseCategory = .other
    /// nil means "use the receipt's default split".
    var split: [ShareEntry]?
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
    var plan = SplitPlan()

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
        plan: SplitPlan = SplitPlan(),
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
        self.plan = plan
        self.existing = existing
    }

    convenience init(parsed: ParsedReceipt, image: Data?) {
        let receiptCategory = ExpenseCategory(raw: parsed.category)
        self.init(
            merchant: parsed.merchant,
            date: Self.parseDate(parsed.date) ?? Date(),
            currency: parsed.currency.isEmpty ? "USD" : parsed.currency,
            category: receiptCategory,
            items: parsed.items.map {
                DraftItem(
                    name: $0.name,
                    quantity: max($0.quantity, 1),
                    cents: $0.lineTotalCents,
                    // No per-item category from the server -> same as the receipt.
                    category: $0.category.flatMap { $0.isEmpty ? nil : ExpenseCategory(raw: $0) } ?? receiptCategory
                )
            },
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
            items: expense.sortedItems.map {
                DraftItem(
                    name: $0.name,
                    quantity: $0.quantity,
                    cents: $0.lineTotalCents,
                    category: $0.category(fallback: expense.category),
                    split: $0.splitOverride
                )
            },
            taxCents: expense.taxCents,
            tipCents: expense.tipCents,
            receiptImage: expense.receiptImage,
            plan: expense.splitPlan,
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

    // MARK: Categories and sharing

    /// The receipt-level category is the default for every item: choosing one
    /// applies it to all items (each can then be changed on its own).
    func setCategoryForAll(_ newCategory: ExpenseCategory) {
        category = newCategory
        for index in items.indices { items[index].category = newCategory }
    }

    private var lines: [LineInput] {
        items.map { LineInput(cents: $0.cents, category: $0.category, override: $0.split) }
    }

    /// Who owes what for the whole receipt, tax and tip included.
    var personTotals: [PersonTotal] {
        ExpenseMath.personTotals(plan: plan, lines: lines, taxCents: taxCents, tipCents: tipCents)
    }

    func split(for item: DraftItem) -> [ShareEntry] { plan.resolve(item.split) }

    /// What share of an item the other person pays, in basis points.
    func otherShare(of item: DraftItem) -> Int { plan.otherShare(in: plan.resolve(item.split)) }

    /// Sets the other person's share of one item. Matching the receipt's
    /// default clears the override, so the item keeps following the default.
    func setOtherShare(_ basisPoints: Int, of itemID: UUID) {
        guard let index = items.firstIndex(where: { $0.id == itemID }) else { return }
        let split = plan.split(otherShare: basisPoints)
        if plan.itemize {
            // Here "no split of its own" means not shared, so 0% clears it and
            // anything else is stored even when it equals the default.
            items[index].split = basisPoints <= 0 ? nil : split
        } else {
            items[index].split = split == plan.defaultSplit ? nil : split
        }
    }

    func isShared(_ item: DraftItem) -> Bool { otherShare(of: item) > 0 }

    /// Itemize mode: switch one item between shared (at the default %) and
    /// just yours.
    func setItemShared(_ shared: Bool, of itemID: UUID) {
        let basisPoints = defaultOtherShare > 0 ? defaultOtherShare : ExpenseMath.whole / 2
        setOtherShare(shared ? basisPoints : 0, of: itemID)
    }

    /// Share all items at one % vs. choosing item by item. Going back to
    /// "all" drops any per-item choices so nothing stale lingers.
    func setItemize(_ on: Bool) {
        plan.itemize = on
        if !on { for index in items.indices { items[index].split = nil } }
    }

    /// What each side pays for one item, in cents: (you, the other person).
    /// Always adds up to the item's amount exactly.
    func amounts(of item: DraftItem) -> (you: Int, other: Int) {
        let theirs = otherShare(of: item)
        let parts = ExpenseMath.allocate(item.cents, weights: [ExpenseMath.whole - theirs, theirs])
        return (parts[0], parts[1])
    }

    var defaultOtherShare: Int { plan.otherShare(in: plan.defaultSplit) }

    /// Changes the share used by every item that doesn't have its own.
    func setDefaultOtherShare(_ basisPoints: Int) {
        plan.customDefault = plan.split(otherShare: basisPoints)
    }

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

        // Splits are only stored for shared expenses; turning sharing off
        // means everything is yours again, so no stale splits are kept.
        expense.isShared = plan.isShared
        expense.splitData = plan.isShared
            ? try? JSONEncoder().encode(SplitSnapshot(participants: plan.participants, defaultSplit: plan.customDefault, itemize: plan.itemize))
            : nil

        for old in expense.items { context.delete(old) }
        expense.items = items.enumerated().map { index, item in
            ExpenseItem(
                name: item.name,
                quantity: item.quantity,
                lineTotalCents: item.cents,
                position: index,
                categoryRaw: item.category.rawValue,
                splitData: plan.isShared ? item.split.flatMap { try? JSONEncoder().encode($0) } : nil
            )
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
