import SwiftUI
import SwiftData

/// One month: its total, where it went, and a row per day with spending.
struct MonthView: View {
    let month: Date
    let currency: String

    @Query private var expenses: [Expense]

    init(month: Date, currency: String) {
        self.month = month
        self.currency = currency
        let interval = Calendar.current.dateInterval(of: .month, for: month)
            ?? DateInterval(start: month, duration: 31 * 86_400)
        let start = interval.start
        let end = interval.end
        _expenses = Query(
            filter: #Predicate<Expense> { $0.date >= start && $0.date < end },
            sort: [SortDescriptor(\Expense.date, order: .reverse)]
        )
    }

    private var spends: [Spend] { expenses.map(\.spend) }
    private var days: [DayTotal] { SpendStats.dailyTotals(spends, currency: currency) }
    private var isCurrentMonth: Bool { Calendar.current.isDate(month, equalTo: Date(), toGranularity: .month) }

    var body: some View {
        List {
            Section {
                PeriodCard(
                    title: isCurrentMonth ? "Month to date" : "Total for the month",
                    spends: spends,
                    currency: currency
                )
            } footer: {
                if expenses.contains(where: \.isShared) {
                    Text("Counts only your share of shared receipts.")
                }
            }

            Section("By day") {
                if days.isEmpty {
                    Text("Nothing spent this month.").foregroundStyle(.secondary)
                }
                let largest = days.map(\.cents).max() ?? 1
                ForEach(days) { day in
                    NavigationLink(value: DashboardRoute.day(day.day)) {
                        BarRow(
                            title: day.day.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day()),
                            subtitle: "\(day.count) receipt\(day.count == 1 ? "" : "s")",
                            cents: day.cents,
                            largest: largest,
                            currency: currency
                        )
                    }
                }
            }
        }
        .navigationTitle(month.formatted(.dateTime.month(.wide).year()))
        .navigationBarTitleDisplayMode(.inline)
    }
}
