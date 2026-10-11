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

    init(name: String, quantity: Int, lineTotalCents: Int, position: Int) {
        self.name = name
        self.quantity = quantity
        self.lineTotalCents = lineTotalCents
        self.position = position
    }
}
