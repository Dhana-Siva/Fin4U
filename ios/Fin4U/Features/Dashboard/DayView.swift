import SwiftUI
import SwiftData

/// The receipts from one day. Tap one to review or correct it.
struct DayView: View {
    let day: Date
    let currency: String

    @Environment(\.modelContext) private var context
    @Query private var expenses: [Expense]
    @State private var editingDraft: ExpenseDraft?

    init(day: Date, currency: String) {
        self.day = day
        self.currency = currency
        let interval = Calendar.current.dateInterval(of: .day, for: day)
            ?? DateInterval(start: day, duration: 86_400)
        let start = interval.start
        let end = interval.end
        _expenses = Query(
            filter: #Predicate<Expense> { $0.date >= start && $0.date < end },
            sort: [SortDescriptor(\Expense.createdAt, order: .reverse)]
        )
    }

    var body: some View {
        List {
            Section {
                PeriodCard(
                    title: day.formatted(.dateTime.weekday(.wide).month(.wide).day().year()),
                    spends: expenses.map(\.spend),
                    currency: currency,
                    showCategories: false
                )
            } footer: {
                if expenses.contains(where: \.isShared) {
                    Text("Counts only your share of the shared receipts.")
                }
            }

            Section("Receipts") {
                if expenses.isEmpty {
                    Text("No receipts on this day.").foregroundStyle(.secondary)
                }
                ForEach(expenses) { expense in
                    Button {
                        editingDraft = ExpenseDraft(expense: expense)
                    } label: {
                        ExpenseRow(expense: expense)
                    }
                    .buttonStyle(.plain)
                }
                .onDelete { offsets in
                    for index in offsets { context.delete(expenses[index]) }
                    try? context.save()
                }
            }
        }
        .navigationTitle(day.formatted(.dateTime.month(.abbreviated).day()))
        .navigationBarTitleDisplayMode(.inline)
        .expenseEditor($editingDraft)
    }
}
