#if DEBUG
import Foundation
import SwiftData

/// Debug builds only, and only when launched with `-seedDemoData`: replaces
/// the store's expenses with a spread across months and days, so the
/// dashboard can be checked without scanning dozens of receipts.
enum DemoData {
    static var requested: Bool { ProcessInfo.processInfo.arguments.contains("-seedDemoData") }

    @MainActor
    static func seed(into context: ModelContext) {
        try? context.delete(model: Expense.self)

        let calendar = Calendar.current
        func day(_ year: Int, _ month: Int, _ day: Int) -> Date {
            calendar.date(from: DateComponents(year: year, month: month, day: day, hour: 12)) ?? Date()
        }
        func add(_ merchant: String, _ date: Date, _ category: ExpenseCategory, _ items: [(String, Int, ExpenseCategory)],
                 tax: Int = 0, shared: Bool = false, settled: Bool = false) {
            let subtotal = items.reduce(0) { $0 + $1.1 }
            let expense = Expense(
                merchant: merchant, date: date, currency: "USD", category: category,
                subtotalCents: subtotal, taxCents: tax, tipCents: 0, totalCents: subtotal + tax, receiptImage: nil
            )
            context.insert(expense)
            expense.items = items.enumerated().map { index, item in
                ExpenseItem(name: item.0, quantity: 1, lineTotalCents: item.1, position: index, categoryRaw: item.2.rawValue)
            }
            if shared {
                let sam = Participant(id: "demo-sam", name: "Sam")
                expense.isShared = true
                expense.isSettled = settled
                expense.splitData = try? JSONEncoder().encode(SplitSnapshot(participants: [sam], defaultSplit: nil, itemize: nil))
            }
        }

        let now = Date()
        let year = calendar.component(.year, from: now)
        let month = calendar.component(.month, from: now)

        add("Shoprite", day(year - 1, 12, 20), .groceries, [("Groceries", 8400, .groceries)], tax: 300)
        add("Green Valley Market", day(year, 1, 6), .groceries, [("Produce", 3200, .groceries), ("Vitamins", 1500, .health)], tax: 200)
        add("Corner Cafe", day(year, 2, 14), .dining, [("Brunch", 4200, .dining)], tax: 350)
        add("Uber", day(year, 3, 3), .transport, [("Ride", 2300, .transport)])
        add("Target", day(year, 4, 18), .shopping, [("Shirt", 2900, .shopping), ("Shampoo", 800, .health)], tax: 260)
        add("Shoprite", day(year, 6, 9), .groceries, [("Groceries", 11_000, .groceries)], tax: 450)
        add("Cinema", day(year, 8, 22), .entertainment, [("Tickets", 3200, .entertainment)])

        // The current month: several receipts across a few days.
        let d1 = 2
        add("Shoprite", day(year, month, d1), .groceries,
            [("Milk", 429, .groceries), ("Bread", 599, .groceries), ("Ibuprofen", 899, .health)], tax: 120, shared: true, settled: true)
        add("Thai Garden", day(year, month, d1), .dining, [("Dinner", 5400, .dining)], tax: 480, shared: true)
        add("Pharmacy", day(year, month, d1 + 3), .health, [("Cold medicine", 1299, .health)], tax: 90)
        add("Green Valley Market", day(year, month, d1 + 6), .groceries,
            [("Bananas", 189, .groceries), ("Chicken", 1124, .groceries)], tax: 80)

        try? context.save()
    }
}
#endif
