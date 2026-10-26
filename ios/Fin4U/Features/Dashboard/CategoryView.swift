import SwiftUI
import SwiftData

/// One category for one period (a month or a year): its total, which
/// merchants it went to, and every expense that contributed. Amounts are the
/// owner's share of that category only -- a Shoprite trip shows just its
/// health items under Health.
struct CategoryView: View {
    let category: ExpenseCategory
    let interval: DateInterval
    let periodTitle: String
    let currency: String

    @Query private var expenses: [Expense]
    @State private var editingDraft: ExpenseDraft?

    init(category: ExpenseCategory, interval: DateInterval, periodTitle: String, currency: String) {
        self.category = category
        self.interval = interval
        self.periodTitle = periodTitle
        self.currency = currency
        let start = interval.start
        let end = interval.end
        _expenses = Query(
            filter: #Predicate<Expense> { $0.date >= start && $0.date < end },
            sort: [SortDescriptor(\Expense.date, order: .reverse)]
        )
    }

    private var entries: [CategoryBreakdown.Entry] {
        CategoryBreakdown.entries(expenses, category: category, currency: currency)
    }

    var body: some View {
        let entries = entries
        let total = entries.reduce(0) { $0 + $1.cents }
        List {
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Label(periodTitle, systemImage: category.symbol)
                        .font(.subheadline)
                        .foregroundStyle(category.color)
                    Text(Money.format(total, currency: currency))
                        .font(.system(size: 34, weight: .bold, design: .rounded))
                        .monospacedDigit()
                    Text(entries.count == 1 ? "1 expense" : "\(entries.count) expenses")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)
            }

            let merchants = CategoryBreakdown.byMerchant(entries)
            if merchants.count > 1 {
                Section("By merchant") {
                    let largest = max(merchants.map(\.cents).max() ?? 1, 1)
                    ForEach(merchants, id: \.name) { merchant in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text(merchant.name).lineLimit(1)
                                if merchant.count > 1 {
                                    Text("×\(merchant.count)")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Text(Money.format(merchant.cents, currency: currency))
                                    .monospacedDigit()
                            }
                            ProgressView(value: Double(max(merchant.cents, 0)), total: Double(largest))
                                .tint(category.color)
                        }
                    }
                }
            }

            Section("Expenses") {
                if entries.isEmpty {
                    Text("Nothing in \(category.title) for \(periodTitle).").foregroundStyle(.secondary)
                }
                ForEach(entries, id: \.expense.id) { entry in
                    Button {
                        editingDraft = ExpenseDraft(expense: entry.expense)
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(entry.expense.merchant)
                                    .font(.body.weight(.medium))
                                    .lineLimit(1)
                                Text(subtitle(for: entry))
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text(Money.format(entry.cents, currency: currency))
                                .font(.body.weight(.semibold))
                                .monospacedDigit()
                                .foregroundStyle(entry.cents < 0 ? .green : .primary)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .navigationTitle(category.title)
        .navigationBarTitleDisplayMode(.inline)
        .expenseEditor($editingDraft)
    }

    private func subtitle(for entry: CategoryBreakdown.Entry) -> String {
        var parts = [entry.expense.date.formatted(.dateTime.month(.abbreviated).day())]
        // A mixed receipt only partly counts here; show what it was in full.
        if entry.cents != entry.expense.myTotalCents {
            parts.append("part of \(Money.format(entry.expense.myTotalCents, currency: currency))")
        }
        if !entry.expense.statementSource.isEmpty {
            parts.append(entry.expense.statementSource)
        }
        return parts.joined(separator: " · ")
    }
}

/// Pure grouping logic for `CategoryView`, kept out of the view for tests.
enum CategoryBreakdown {
    struct Entry {
        let expense: Expense
        let cents: Int
    }

    struct Merchant: Equatable {
        let name: String
        let cents: Int
        let count: Int
    }

    /// Expenses that put anything into `category`, with just that amount.
    static func entries(_ expenses: [Expense], category: ExpenseCategory, currency: String) -> [Entry] {
        expenses
            .filter { $0.currency == currency }
            .compactMap { expense in
                let cents = expense.myCategoryTotals[category] ?? 0
                return cents == 0 ? nil : Entry(expense: expense, cents: cents)
            }
    }

    /// Same merchant name (ignoring case and spacing) adds up; biggest first.
    static func byMerchant(_ entries: [Entry]) -> [Merchant] {
        var totals: [String: (name: String, cents: Int, count: Int)] = [:]
        for entry in entries {
            let name = entry.expense.merchant.trimmingCharacters(in: .whitespacesAndNewlines)
            let key = name.lowercased()
            let current = totals[key] ?? (name: name, cents: 0, count: 0)
            totals[key] = (current.name, current.cents + entry.cents, current.count + 1)
        }
        return totals.values
            .map { Merchant(name: $0.name, cents: $0.cents, count: $0.count) }
            .sorted { $0.cents != $1.cents ? $0.cents > $1.cents : $0.name < $1.name }
    }
}
