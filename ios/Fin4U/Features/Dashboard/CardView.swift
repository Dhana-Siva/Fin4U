import SwiftUI
import SwiftData

/// One card's spending for a period: the total, what it went on by category,
/// and every expense paid with it. Tap an expense to edit it (including
/// which card it was paid with).
struct CardView: View {
    let card: String
    let interval: DateInterval
    let periodTitle: String
    let currency: String

    @Query private var expenses: [Expense]
    @State private var editingDraft: ExpenseDraft?

    init(card: String, interval: DateInterval, periodTitle: String, currency: String) {
        self.card = card
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

    private var matching: [Expense] {
        expenses.filter { $0.currency == currency && $0.card == card }
    }

    var body: some View {
        let matching = matching
        let spends = matching.map(\.spend)
        List {
            Section {
                PeriodCard(title: periodTitle, spends: spends, currency: currency, showCategories: false)
            } footer: {
                if card.isEmpty {
                    Text("Expenses without a card. Open one and set \"Paid with\" to move it to a card.")
                }
            }

            let categories = SpendStats.categoryTotals(spends, currency: currency)
            if !categories.isEmpty {
                Section("By category") {
                    CategoryBars(totals: categories, currency: currency)
                }
            }

            Section("Expenses") {
                if matching.isEmpty {
                    Text("Nothing on this card for \(periodTitle).").foregroundStyle(.secondary)
                }
                ForEach(matching) { expense in
                    Button {
                        editingDraft = ExpenseDraft(expense: expense)
                    } label: {
                        ExpenseRow(expense: expense)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .navigationTitle(card.cardTitle)
        .navigationBarTitleDisplayMode(.inline)
        .expenseEditor($editingDraft)
    }
}
