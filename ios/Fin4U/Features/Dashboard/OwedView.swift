import SwiftUI
import SwiftData

/// Every shared receipt someone still owes money on. Swipe a receipt to mark
/// it paid back; tap it to see or change how it was split.
struct OwedView: View {
    let currency: String

    @Environment(\.modelContext) private var context
    @Query(
        filter: #Predicate<Expense> { $0.isShared && !$0.isSettled },
        sort: [SortDescriptor(\Expense.date, order: .reverse)]
    )
    private var sharedExpenses: [Expense]
    @State private var editingDraft: ExpenseDraft?

    /// Shared receipts where someone really does owe something (a 0% split
    /// leaves nothing to collect).
    private var expenses: [Expense] { sharedExpenses.filter { !$0.owedToMe.isEmpty } }

    var body: some View {
        List {
            Section {
                OwedCard(spends: expenses.map(\.spend), currency: currency)
            } footer: {
                Text("Assumes you paid the whole bill. Swipe a receipt left when it's been paid back.")
            }

            Section("Receipts") {
                if expenses.isEmpty {
                    Text("Nobody owes you anything.").foregroundStyle(.secondary)
                }
                ForEach(expenses) { expense in
                    Button {
                        editingDraft = ExpenseDraft(expense: expense)
                    } label: {
                        row(expense)
                    }
                    .buttonStyle(.plain)
                    .swipeActions(edge: .trailing) {
                        Button {
                            expense.isSettled = true
                            try? context.save()
                        } label: {
                            Label("Paid back", systemImage: "checkmark.circle.fill")
                        }
                        .tint(.green)
                    }
                }
            }
        }
        .navigationTitle("Owed to you")
        .navigationBarTitleDisplayMode(.inline)
        .expenseEditor($editingDraft)
    }

    private func row(_ expense: Expense) -> some View {
        let owed = expense.owedToMe
        return HStack(spacing: 12) {
            Image(systemName: expense.category.symbol)
                .foregroundStyle(.white)
                .frame(width: 36, height: 36)
                .background(expense.category.color.gradient, in: Circle())

            VStack(alignment: .leading, spacing: 2) {
                Text(expense.merchant).font(.body.weight(.medium)).lineLimit(1)
                Text(expense.date.formatted(.dateTime.month(.abbreviated).day()) + " · " +
                     owed.map(\.name).joined(separator: ", "))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Text(Money.format(owed.reduce(0) { $0 + $1.cents }, currency: expense.currency))
                .font(.body.weight(.semibold))
                .monospacedDigit()
        }
        .contentShape(Rectangle())
    }
}
