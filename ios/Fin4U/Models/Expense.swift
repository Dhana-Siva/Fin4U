import Foundation
import SwiftData

/// A saved expense. Lives only on this phone (SwiftData, local store) --
/// there is no account and no server-side copy.
@Model
final class Expense {
    var id: UUID
    var merchant: String
    var date: Date
    var currency: String
    var categoryRaw: String
    var subtotalCents: Int
    var taxCents: Int
    var tipCents: Int
    var totalCents: Int
    var createdAt: Date
    /// The (downscaled) receipt photo, kept on-device so the user can check
    /// what they actually bought. Never sent anywhere after the scan.
    @Attribute(.externalStorage) var receiptImage: Data?
    @Relationship(deleteRule: .cascade, inverse: \ExpenseItem.expense)
    var items: [ExpenseItem] = []
    /// Defaults are required so stores saved before sharing existed migrate.
    var isShared: Bool = false
    /// JSON `SplitSnapshot` (who it's shared with + any hand-edited default).
    var splitData: Data?

    var category: ExpenseCategory {
        get { ExpenseCategory(raw: categoryRaw) }
        set { categoryRaw = newValue.rawValue }
    }

    /// SwiftData relationships are unordered; `position` restores receipt order.
    var sortedItems: [ExpenseItem] {
        items.sorted { $0.position < $1.position }
    }

    init(
        merchant: String,
        date: Date,
        currency: String,
        category: ExpenseCategory,
        subtotalCents: Int,
        taxCents: Int,
        tipCents: Int,
        totalCents: Int,
        receiptImage: Data?
    ) {
        self.id = UUID()
        self.merchant = merchant
        self.date = date
        self.currency = currency
        self.categoryRaw = category.rawValue
        self.subtotalCents = subtotalCents
        self.taxCents = taxCents
        self.tipCents = tipCents
        self.totalCents = totalCents
        self.createdAt = Date()
        self.receiptImage = receiptImage
    }
}

@Model
final class ExpenseItem {
    var name: String
    var quantity: Int
    var lineTotalCents: Int
    var position: Int
    var expense: Expense?
    /// Empty (also for items saved before per-item categories) means "same
    /// as the receipt".
    var categoryRaw: String = ""
    /// JSON `[ShareEntry]`; nil means "use the receipt's default split".
    var splitData: Data?

    init(
        name: String,
        quantity: Int,
        lineTotalCents: Int,
        position: Int,
        categoryRaw: String = "",
        splitData: Data? = nil
    ) {
        self.name = name
        self.quantity = quantity
        self.lineTotalCents = lineTotalCents
        self.position = position
        self.categoryRaw = categoryRaw
        self.splitData = splitData
    }

    func category(fallback: ExpenseCategory) -> ExpenseCategory {
        categoryRaw.isEmpty ? fallback : ExpenseCategory(raw: categoryRaw)
    }

    var splitOverride: [ShareEntry]? {
        splitData.flatMap { try? JSONDecoder().decode([ShareEntry].self, from: $0) }
    }
}

// MARK: - What this expense means for the phone's owner

extension Expense {
    var splitPlan: SplitPlan {
        var plan = SplitPlan()
        plan.isShared = isShared
        if let data = splitData, let snapshot = try? JSONDecoder().decode(SplitSnapshot.self, from: data) {
            plan.participants = snapshot.participants
            plan.customDefault = snapshot.defaultSplit
            plan.itemize = snapshot.itemize ?? false
        }
        return plan
    }

    private var lines: [LineInput] {
        sortedItems.map {
            LineInput(cents: $0.lineTotalCents, category: $0.category(fallback: category), override: $0.splitOverride)
        }
    }

    var personTotals: [PersonTotal] {
        ExpenseMath.personTotals(plan: splitPlan, lines: lines, taxCents: taxCents, tipCents: tipCents)
    }

    /// The owner's own share -- equal to `totalCents` unless it's shared.
    var myTotalCents: Int {
        personTotals.first { $0.id == Participant.me.id }?.cents ?? totalCents
    }

    var myCategoryTotals: [ExpenseCategory: Int] {
        ExpenseMath.categoryTotals(
            for: Participant.me.id, plan: splitPlan, lines: lines,
            taxCents: taxCents, tipCents: tipCents, receiptCategory: category
        )
    }
}
