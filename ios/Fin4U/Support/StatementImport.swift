import Foundation
import SwiftData

/// One statement transaction on the review screen: whether it will be saved,
/// its (editable) category, and why it might be unticked.
struct StatementLine: Identifiable, Equatable {
    let id = UUID()
    let transaction: StatementTransaction
    let date: Date
    var category: ExpenseCategory
    var include: Bool
    /// A saved expense that looks like the same charge (same amount, date
    /// within a few days) -- most often the receipt the user already scanned.
    var duplicateOf: String?

    var merchant: String {
        let name = transaction.merchant.trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty ? transaction.description : name
    }

    var isRefund: Bool { transaction.amountCents < 0 }
}

/// Turns a parsed statement into review lines and, after review, expenses.
/// Pure logic (no UI) so the rules are unit-tested.
enum StatementImport {
    /// Card statements post a few days after the purchase, so a receipt dated
    /// the 3rd can show up on the statement as the 5th.
    static let duplicateWindowDays = 3

    struct Existing {
        let label: String
        let date: Date
        let totalCents: Int
    }

    /// Payments to the card are dropped entirely -- moving money to the card
    /// isn't spending. Lines matching an existing expense start unticked.
    static func lines(
        for statement: ParsedStatement,
        existing: [Existing],
        calendar: Calendar = .current
    ) -> [StatementLine] {
        let fallbackDate = ExpenseDraft.parseDate(statement.periodEnd) ?? Date()
        var unmatched = existing
        return statement.transactions
            .filter { $0.kind != .payment }
            .map { transaction in
                let date = ExpenseDraft.parseDate(transaction.date) ?? fallbackDate
                var line = StatementLine(
                    transaction: transaction,
                    date: date,
                    category: ExpenseCategory(raw: transaction.category),
                    include: true
                )
                // Each saved expense can explain at most one statement line.
                if let index = unmatched.firstIndex(where: {
                    matches(amount: transaction.amountCents, date: date, existing: $0, calendar: calendar)
                }) {
                    line.duplicateOf = unmatched[index].label
                    line.include = false
                    unmatched.remove(at: index)
                }
                return line
            }
    }

    static func matches(amount: Int, date: Date, existing: Existing, calendar: Calendar) -> Bool {
        guard amount == existing.totalCents else { return false }
        let a = calendar.startOfDay(for: date)
        let b = calendar.startOfDay(for: existing.date)
        let days = abs(calendar.dateComponents([.day], from: a, to: b).day ?? .max)
        return days <= duplicateWindowDays
    }

    static func existing(from expenses: [Expense]) -> [Existing] {
        expenses.map { Existing(label: $0.merchant, date: $0.date, totalCents: $0.totalCents) }
    }

    /// A short source label stored on each imported expense, e.g. "Chase Sapphire ••4242".
    static func sourceLabel(for statement: ParsedStatement) -> String {
        let issuer = statement.issuer.trimmingCharacters(in: .whitespacesAndNewlines)
        let card = statement.cardLast4.isEmpty ? "" : "••\(statement.cardLast4)"
        let label = [issuer.isEmpty ? "Card statement" : issuer, card].filter { !$0.isEmpty }.joined(separator: " ")
        return label
    }

    /// Saves every ticked line as its own expense: one item carrying the
    /// whole amount, so the existing category and dashboard math apply
    /// unchanged (a refund is a negative item and reduces its category).
    @discardableResult
    static func save(_ lines: [StatementLine], currency: String, source: String, in context: ModelContext) -> [Expense] {
        lines.filter(\.include).map { line in
            let cents = line.transaction.amountCents
            let expense = Expense(
                merchant: line.merchant,
                date: line.date,
                currency: currency.isEmpty ? "USD" : currency,
                category: line.category,
                subtotalCents: cents,
                taxCents: 0,
                tipCents: 0,
                totalCents: cents,
                receiptImage: nil
            )
            expense.statementSource = source
            expense.paidWith = source
            context.insert(expense)
            expense.items = [
                ExpenseItem(
                    name: line.transaction.description.isEmpty ? line.merchant : line.transaction.description,
                    quantity: 1,
                    lineTotalCents: cents,
                    position: 0,
                    categoryRaw: line.category.rawValue
                ),
            ]
            return expense
        }
    }
}
