import SwiftUI
import SwiftData

extension ExpenseDraft: Identifiable {
    var id: ObjectIdentifier { ObjectIdentifier(self) }
}

struct HomeView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: [
        SortDescriptor(\Expense.date, order: .reverse),
        SortDescriptor(\Expense.createdAt, order: .reverse),
    ])
    private var expenses: [Expense]

    @State private var scanning = false
    @State private var editingDraft: ExpenseDraft?

    private var thisMonth: [Expense] {
        expenses.filter { Calendar.current.isDate($0.date, equalTo: Date(), toGranularity: .month) }
    }

    var body: some View {
        NavigationStack {
            List {
                if expenses.isEmpty {
                    emptyState
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                } else {
                    Section {
                        MonthSummaryCard(expenses: thisMonth, fallbackCurrency: expenses.first?.currency ?? "USD")
                    }
                    Section("Recent") {
                        ForEach(expenses) { expense in
                            Button {
                                editingDraft = ExpenseDraft(expense: expense)
                            } label: {
                                ExpenseRow(expense: expense)
                            }
                            .buttonStyle(.plain)
                        }
                        .onDelete(perform: delete)
                    }
                }
            }
            .navigationTitle("Fin4U")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button { scanning = true } label: {
                        Label("Scan receipt", systemImage: "camera.viewfinder")
                    }
                }
            }
            .fullScreenCover(isPresented: $scanning) {
                ScanFlowView()
            }
            .sheet(item: $editingDraft) { draft in
                NavigationStack {
                    ReviewView(draft: draft, onClose: { editingDraft = nil })
                }
            }
        }
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label("No expenses yet", systemImage: "doc.text.viewfinder")
        } description: {
            Text("Scan a receipt and Fin4U will itemize it for you.")
        } actions: {
            Button("Scan a receipt") { scanning = true }
                .buttonStyle(.borderedProminent)
        }
    }

    private func delete(at offsets: IndexSet) {
        for index in offsets { context.delete(expenses[index]) }
        try? context.save()
    }
}

struct ExpenseRow: View {
    let expense: Expense

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: expense.category.symbol)
                .foregroundStyle(.white)
                .frame(width: 36, height: 36)
                .background(expense.category.color.gradient, in: Circle())

            VStack(alignment: .leading, spacing: 2) {
                Text(expense.merchant)
                    .font(.body.weight(.medium))
                    .lineLimit(1)
                Text(subtitle)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Text(Money.format(expense.totalCents, currency: expense.currency))
                .font(.body.weight(.semibold))
                .monospacedDigit()
        }
        .contentShape(Rectangle())
    }

    private var subtitle: String {
        let date = expense.date.formatted(.dateTime.month(.abbreviated).day())
        let count = expense.items.count
        return count > 0 ? "\(date) · \(count) item\(count == 1 ? "" : "s")" : date
    }
}

/// This month's total plus a per-category breakdown. Totals are per
/// currency (adding dollars to rupees would be nonsense); the breakdown
/// covers the main one.
struct MonthSummaryCard: View {
    let expenses: [Expense]
    let fallbackCurrency: String

    private var totalsByCurrency: [(currency: String, total: Int)] {
        Dictionary(grouping: expenses, by: \.currency)
            .map { (currency: $0.key, total: $0.value.reduce(0) { $0 + $1.totalCents }) }
            .sorted { $0.total > $1.total }
    }

    private var primaryCurrency: String { totalsByCurrency.first?.currency ?? fallbackCurrency }

    private var categoryTotals: [(category: ExpenseCategory, total: Int)] {
        Dictionary(grouping: expenses.filter { $0.currency == primaryCurrency }, by: \.category)
            .map { (category: $0.key, total: $0.value.reduce(0) { $0 + $1.totalCents }) }
            .sorted { $0.total > $1.total }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(Date().formatted(.dateTime.month(.wide).year()))
                .font(.subheadline)
                .foregroundStyle(.secondary)

            if expenses.isEmpty {
                Text("Nothing spent yet this month.")
                    .font(.headline)
            } else {
                Text(Money.format(totalsByCurrency.first?.total ?? 0, currency: primaryCurrency))
                    .font(.system(size: 36, weight: .bold, design: .rounded))
                    .monospacedDigit()

                ForEach(totalsByCurrency.dropFirst(), id: \.currency) { entry in
                    Text("+ \(Money.format(entry.total, currency: entry.currency))")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                let largest = max(categoryTotals.map(\.total).max() ?? 1, 1)
                ForEach(categoryTotals, id: \.category) { entry in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Label(entry.category.title, systemImage: entry.category.symbol)
                                .font(.footnote)
                                .foregroundStyle(entry.category.color)
                            Spacer()
                            Text(Money.format(entry.total, currency: primaryCurrency))
                                .font(.footnote)
                                .monospacedDigit()
                        }
                        ProgressView(value: Double(max(entry.total, 0)), total: Double(largest))
                            .tint(entry.category.color)
                    }
                }
            }
        }
        .padding(.vertical, 4)
    }
}
