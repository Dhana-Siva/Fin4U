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

    @Environment(Profile.self) private var profile
    @State private var showingProfile = false
    @State private var scanning = false
    @State private var editingDraft: ExpenseDraft?
    @State private var shownYear = Calendar.current.component(.year, from: Date())
    @State private var path: [DashboardRoute] = []

    private let calendar = Calendar.current

    private var spends: [Spend] { expenses.map(\.spend) }
    private var currency: String { SpendStats.primaryCurrency(spends) }
    private var currentYear: Int { calendar.component(.year, from: Date()) }
    private var availableYears: ClosedRange<Int> { SpendStats.years(spends) }

    private func spends(inYear year: Int) -> [Spend] {
        spends.filter { calendar.component(.year, from: $0.date) == year }
    }

    private var thisMonth: [Spend] {
        spends.filter { calendar.isDate($0.date, equalTo: Date(), toGranularity: .month) }
    }

    private var firstOfThisMonth: Date {
        calendar.dateInterval(of: .month, for: Date())?.start ?? Date()
    }

    var body: some View {
        NavigationStack(path: $path) {
            List {
                if expenses.isEmpty {
                    emptyState
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                } else {
                    yearSection
                    chartSection
                    monthToDateSection
                    owedSection
                    byMonthSection
                    recentSection
                }
            }
            .navigationTitle(Greeting.title(
                firstName: profile.firstName,
                hour: calendar.component(.hour, from: Date())
            ))
            .navigationDestination(for: DashboardRoute.self) { route in
                switch route {
                case .month(let month): MonthView(month: month, currency: currency)
                case .day(let day): DayView(day: day, currency: currency)
                case .owed: OwedView(currency: currency)
                }
            }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { showingProfile = true } label: {
                        AvatarView(size: 32)
                    }
                    .accessibilityLabel("Profile")
                }
                ToolbarItem(placement: .primaryAction) {
                    Button { scanning = true } label: {
                        Label("Scan receipt", systemImage: "camera.viewfinder")
                    }
                }
            }
            .fullScreenCover(isPresented: $scanning) {
                ScanFlowView()
            }
            .sheet(isPresented: $showingProfile) {
                ProfileView()
            }
            .expenseEditor($editingDraft)
            .task {
                #if DEBUG
                if DemoData.requested { DemoData.seed(into: context) }
                #endif
            }
        }
    }

    // MARK: Minimising sections

    @AppStorage("dashboardCollapsedSections") private var collapsedRaw = ""

    private func isExpanded(_ section: DashboardSection) -> Bool {
        !CollapsedSections(raw: collapsedRaw).contains(section)
    }

    private func toggle(_ section: DashboardSection) {
        var collapsed = CollapsedSections(raw: collapsedRaw)
        collapsed.toggle(section)
        withAnimation(.easeInOut(duration: 0.2)) { collapsedRaw = collapsed.raw }
    }

    private func header(_ section: DashboardSection, _ title: String, summary: String? = nil, prominent: Bool = false) -> some View {
        CollapsibleHeader(
            title: title,
            isExpanded: isExpanded(section),
            summary: summary,
            prominent: prominent
        ) { toggle(section) }
    }

    private func money(_ cents: Int) -> String { Money.format(cents, currency: currency) }

    // MARK: Sections

    private var yearSection: some View {
        let yearSpends = spends(inYear: shownYear)
        return Section {
            if isExpanded(.summary) {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Button { shownYear -= 1 } label: { Image(systemName: "chevron.left") }
                            .disabled(shownYear <= availableYears.lowerBound)
                        Spacer()
                        Text(verbatim: String(shownYear)).font(.headline)
                        Spacer()
                        Button { shownYear += 1 } label: { Image(systemName: "chevron.right") }
                            .disabled(shownYear >= currentYear)
                    }
                    .buttonStyle(.borderless)

                    PeriodCard(
                        title: shownYear == currentYear ? "Year to date" : "Total for \(String(shownYear))",
                        spends: yearSpends,
                        currency: currency
                    )
                }
            }
        } header: {
            header(.summary, "Your expenses summary",
                   summary: money(SpendStats.total(yearSpends, currency: currency)), prominent: true)
        }
    }

    private var chartSection: some View {
        let totals = SpendStats.monthlyTotals(spends, year: shownYear, currency: currency)
        return Section {
            if isExpanded(.chart) {
                if totals.isEmpty {
                    Text("Nothing spent in \(String(shownYear)).").foregroundStyle(.secondary)
                } else {
                    MonthlyChart(
                        series: SpendStats.monthSeries(totals),
                        currency: currency,
                        highlightedMonth: shownYear == currentYear ? calendar.component(.month, from: Date()) : nil
                    ) { month in
                        if let first = calendar.date(from: DateComponents(year: shownYear, month: month, day: 1)) {
                            path.append(.month(first))
                        }
                    }
                }
            }
        } header: {
            header(.chart, "Spend by month, \(String(shownYear))")
        } footer: {
            if isExpanded(.chart), !totals.isEmpty { Text("Tap a bar to open that month.") }
        }
    }

    private var monthToDateSection: some View {
        Section {
            if isExpanded(.monthToDate) {
                NavigationLink(value: DashboardRoute.month(firstOfThisMonth)) {
                    PeriodCard(
                        title: Date().formatted(.dateTime.month(.wide).year()),
                        spends: thisMonth,
                        currency: currency,
                        showCategories: false
                    )
                }
            }
        } header: {
            header(.monthToDate, "Month to date",
                   summary: money(SpendStats.total(thisMonth, currency: currency)))
        }
    }

    /// A running balance across all time (not just the year on screen), shown
    /// only while someone actually owes something.
    @ViewBuilder
    private var owedSection: some View {
        let owed = SpendStats.totalOwed(spends, currency: currency)
        if owed > 0 {
            Section {
                if isExpanded(.owed) {
                    NavigationLink(value: DashboardRoute.owed) {
                        OwedCard(spends: spends, currency: currency, showTitle: false)
                    }
                }
            } header: {
                header(.owed, "Owed to you", summary: money(owed))
            }
        }
    }

    private var byMonthSection: some View {
        let totals = SpendStats.monthlyTotals(spends, year: shownYear, currency: currency)
        let lastMonth = shownYear == currentYear ? calendar.component(.month, from: Date()) : 12
        let months = (1...lastMonth).reversed().filter { totals[$0] != nil }
        let largest = totals.values.max() ?? 1

        return Section {
            if isExpanded(.byMonth) {
                if months.isEmpty {
                    Text("Nothing spent in \(String(shownYear)).").foregroundStyle(.secondary)
                }
                ForEach(months, id: \.self) { month in
                    let first = calendar.date(from: DateComponents(year: shownYear, month: month, day: 1)) ?? Date()
                    NavigationLink(value: DashboardRoute.month(first)) {
                        BarRow(
                            title: first.formatted(.dateTime.month(.wide)),
                            subtitle: nil,
                            cents: totals[month] ?? 0,
                            largest: largest,
                            currency: currency
                        )
                    }
                }
            }
        } header: {
            header(.byMonth, "By month")
        }
    }

    private var recentSection: some View {
        Section {
            if isExpanded(.recent) {
                ForEach(expenses.prefix(5)) { expense in
                    Button {
                        editingDraft = ExpenseDraft(expense: expense)
                    } label: {
                        ExpenseRow(expense: expense)
                    }
                    .buttonStyle(.plain)
                }
                .onDelete(perform: delete)
            }
        } header: {
            header(.recent, "Recent")
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
        let shown = Array(expenses.prefix(5))
        for index in offsets { context.delete(shown[index]) }
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

            VStack(alignment: .trailing, spacing: 2) {
                Text(Money.format(expense.totalCents, currency: expense.currency))
                    .font(.body.weight(.semibold))
                    .monospacedDigit()
                if expense.isShared {
                    Text("Your share \(Money.format(expense.myTotalCents, currency: expense.currency))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
            }
        }
        .contentShape(Rectangle())
    }

    private var subtitle: String {
        let date = expense.date.formatted(.dateTime.month(.abbreviated).day())
        let count = expense.items.count
        var text = count > 0 ? "\(date) · \(count) item\(count == 1 ? "" : "s")" : date
        if expense.isShared { text += expense.isSettled ? " · Paid back" : " · Shared" }
        return text
    }
}
