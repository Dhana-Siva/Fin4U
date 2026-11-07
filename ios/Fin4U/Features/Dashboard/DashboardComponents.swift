import SwiftUI

/// Where a tap on the dashboard leads. The destinations are registered once
/// on the root stack, so any screen in it can link with these values.
enum DashboardRoute: Hashable {
    case month(Date)  // first day of the month
    case day(Date)    // start of the day
    case owed         // everything others still owe
    /// One category's spending between `start` and `end` (end exclusive).
    case category(ExpenseCategory, start: Date, end: Date, title: String)
    /// One card's spending in the period; "" means expenses with no card set.
    case card(String, start: Date, end: Date, title: String)
}

extension String {
    /// Display name for a card value; "" is the "not set" bucket.
    var cardTitle: String { isEmpty ? "No card set" : self }
}

/// A period's headline total plus the same breakdown by category.
struct PeriodCard: View {
    let title: String
    let spends: [Spend]
    let currency: String
    var showCategories = true

    var body: some View {
        let owed = SpendStats.totalOwed(spends, currency: currency)
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Text(Money.format(SpendStats.total(spends, currency: currency), currency: currency))
                .font(.system(size: 34, weight: .bold, design: .rounded))
                .monospacedDigit()

            ForEach(SpendStats.otherCurrencies(spends, besides: currency), id: \.currency) { other in
                Text("+ \(Money.format(other.cents, currency: other.currency))")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            if owed > 0 {
                Label("Owed to you: \(Money.format(owed, currency: currency))", systemImage: "arrow.down.left.circle.fill")
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(Color.accentColor)
            }

            if showCategories {
                CategoryBars(totals: SpendStats.categoryTotals(spends, currency: currency), currency: currency)
            }
        }
        .padding(.vertical, 4)
    }
}

/// What other people still owe, in total and per person.
struct OwedCard: View {
    let spends: [Spend]
    let currency: String
    /// Off when a section header already says "Owed to you".
    var showTitle = true

    var body: some View {
        let people = SpendStats.owed(spends, currency: currency)
        VStack(alignment: .leading, spacing: 10) {
            if showTitle {
                Text("Owed to you")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Text(Money.format(people.reduce(0) { $0 + $1.cents }, currency: currency))
                .font(.system(size: 34, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(Color.accentColor)

            ForEach(people) { person in
                HStack {
                    Text(person.name).font(.body)
                    Spacer()
                    Text(Money.format(person.cents, currency: currency))
                        .font(.body.weight(.medium))
                        .monospacedDigit()
                }
            }
        }
        .padding(.vertical, 4)
    }
}

/// The same bars as `CategoryBars`, but each is its own list row that opens
/// that category's breakdown for the period.
struct CategoryLinks: View {
    let totals: [(category: ExpenseCategory, cents: Int)]
    let currency: String
    let interval: DateInterval
    let periodTitle: String

    var body: some View {
        let largest = max(totals.map(\.cents).max() ?? 1, 1)
        ForEach(totals, id: \.category) { entry in
            NavigationLink(value: DashboardRoute.category(entry.category, start: interval.start, end: interval.end, title: periodTitle)) {
                CategoryBar(category: entry.category, cents: entry.cents, largest: largest, currency: currency)
            }
        }
    }
}

/// One row per card, each opening that card's breakdown for the period.
struct CardLinks: View {
    let totals: [(card: String, cents: Int)]
    let currency: String
    let interval: DateInterval
    let periodTitle: String

    var body: some View {
        let largest = max(totals.map(\.cents).max() ?? 1, 1)
        ForEach(totals, id: \.card) { entry in
            NavigationLink(value: DashboardRoute.card(entry.card, start: interval.start, end: interval.end, title: periodTitle)) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Label(entry.card.cardTitle, systemImage: entry.card.isEmpty ? "questionmark.circle" : "creditcard.fill")
                            .font(.footnote)
                            .foregroundStyle(entry.card.isEmpty ? Color.secondary : Color.accentColor)
                            .lineLimit(1)
                        Spacer()
                        Text(Money.format(entry.cents, currency: currency))
                            .font(.footnote)
                            .monospacedDigit()
                    }
                    ProgressView(value: Double(max(entry.cents, 0)), total: Double(largest))
                        .tint(entry.card.isEmpty ? .gray : .accentColor)
                }
            }
        }
    }
}

struct CategoryBar: View {
    let category: ExpenseCategory
    let cents: Int
    let largest: Int
    let currency: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Label(category.title, systemImage: category.symbol)
                    .font(.footnote)
                    .foregroundStyle(category.color)
                Spacer()
                Text(Money.format(cents, currency: currency))
                    .font(.footnote)
                    .monospacedDigit()
            }
            ProgressView(value: Double(max(cents, 0)), total: Double(largest))
                .tint(category.color)
        }
    }
}

struct CategoryBars: View {
    let totals: [(category: ExpenseCategory, cents: Int)]
    let currency: String

    var body: some View {
        let largest = max(totals.map(\.cents).max() ?? 1, 1)
        ForEach(totals, id: \.category) { entry in
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Label(entry.category.title, systemImage: entry.category.symbol)
                        .font(.footnote)
                        .foregroundStyle(entry.category.color)
                    Spacer()
                    Text(Money.format(entry.cents, currency: currency))
                        .font(.footnote)
                        .monospacedDigit()
                }
                ProgressView(value: Double(max(entry.cents, 0)), total: Double(largest))
                    .tint(entry.category.color)
            }
        }
    }
}

/// A dashboard section heading that minimises or expands its section when
/// tapped. While minimised it can show the section's key figure, so the
/// number is still visible without the detail.
struct CollapsibleHeader: View {
    let title: String
    let isExpanded: Bool
    var summary: String?
    var prominent = false
    let toggle: () -> Void

    var body: some View {
        Button(action: toggle) {
            HStack(spacing: 8) {
                Text(title)
                    .font(prominent ? .title2.bold() : .headline)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Spacer(minLength: 8)
                if !isExpanded, let summary {
                    Text(summary)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
                Image(systemName: "chevron.down")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .rotationEffect(.degrees(isExpanded ? 0 : -90))
            }
            .foregroundColor(.primary)
            .textCase(nil)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(.isHeader)
        .accessibilityValue(isExpanded ? "Expanded" : "Minimised")
        .accessibilityHint(isExpanded ? "Double tap to minimise" : "Double tap to expand")
    }
}

/// A label, an amount and a bar sized against `largest` -- one month in the
/// year list.
struct BarRow: View {
    let title: String
    let subtitle: String?
    let cents: Int
    let largest: Int
    let currency: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.body.weight(.medium))
                    if let subtitle {
                        Text(subtitle).font(.footnote).foregroundStyle(.secondary)
                    }
                }
                Spacer()
                Text(Money.format(cents, currency: currency))
                    .font(.body.weight(.semibold))
                    .monospacedDigit()
            }
            ProgressView(value: Double(max(cents, 0)), total: Double(max(largest, 1)))
                .tint(.accentColor)
        }
        .padding(.vertical, 2)
    }
}

extension View {
    /// The review screen in a sheet, for editing a saved expense.
    func expenseEditor(_ draft: Binding<ExpenseDraft?>) -> some View {
        sheet(item: draft) { current in
            NavigationStack {
                ReviewView(draft: current, onClose: { draft.wrappedValue = nil })
            }
        }
    }
}
