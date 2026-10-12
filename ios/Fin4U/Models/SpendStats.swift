import Foundation

/// One expense reduced to what the dashboard needs: the owner's own share
/// (not the full receipt) and where it falls by category.
struct Spend: Equatable {
    var date: Date
    var currency: String
    var cents: Int
    var categories: [ExpenseCategory: Int]
    /// What others still owe the owner for this expense.
    var owed: [PersonTotal] = []
}

extension Expense {
    var spend: Spend {
        Spend(date: date, currency: currency, cents: myTotalCents, categories: myCategoryTotals, owed: owedToMe)
    }
}

struct DayTotal: Equatable, Identifiable {
    var day: Date  // start of day
    var cents: Int
    var count: Int

    var id: Date { day }
}

/// Totals for the year / month / day views. Amounts in different currencies
/// are never added together, so most of these take the currency to report.
enum SpendStats {
    /// The currency with the most spend overall -- used so every screen
    /// reports in the same one.
    static func primaryCurrency(_ spends: [Spend], fallback: String = "USD") -> String {
        let totals = Dictionary(grouping: spends, by: \.currency).mapValues { $0.reduce(0) { $0 + $1.cents } }
        return totals.max { $0.value < $1.value }?.key ?? fallback
    }

    static func total(_ spends: [Spend], currency: String) -> Int {
        spends.filter { $0.currency == currency }.reduce(0) { $0 + $1.cents }
    }

    /// Totals for every currency other than `currency`, biggest first.
    static func otherCurrencies(_ spends: [Spend], besides currency: String) -> [(currency: String, cents: Int)] {
        Dictionary(grouping: spends.filter { $0.currency != currency }, by: \.currency)
            .map { (currency: $0.key, cents: $0.value.reduce(0) { $0 + $1.cents }) }
            .sorted { $0.cents > $1.cents }
    }

    /// What each person owes in `currency`, biggest debt first.
    static func owed(_ spends: [Spend], currency: String) -> [PersonTotal] {
        var byPerson: [String: PersonTotal] = [:]
        for spend in spends where spend.currency == currency {
            for entry in spend.owed {
                byPerson[entry.id, default: PersonTotal(id: entry.id, name: entry.name, cents: 0)].cents += entry.cents
            }
        }
        return byPerson.values.sorted { $0.cents != $1.cents ? $0.cents > $1.cents : $0.name < $1.name }
    }

    static func totalOwed(_ spends: [Spend], currency: String) -> Int {
        owed(spends, currency: currency).reduce(0) { $0 + $1.cents }
    }

    static func categoryTotals(_ spends: [Spend], currency: String) -> [(category: ExpenseCategory, cents: Int)] {
        var totals: [ExpenseCategory: Int] = [:]
        for spend in spends where spend.currency == currency {
            for (category, cents) in spend.categories { totals[category, default: 0] += cents }
        }
        return totals.map { (category: $0.key, cents: $0.value) }.sorted { $0.cents > $1.cents }
    }

    /// Month number (1...12) -> total, for one year.
    static func monthlyTotals(_ spends: [Spend], year: Int, currency: String, calendar: Calendar = .current) -> [Int: Int] {
        var result: [Int: Int] = [:]
        for spend in spends where spend.currency == currency {
            let parts = calendar.dateComponents([.year, .month], from: spend.date)
            if parts.year == year, let month = parts.month { result[month, default: 0] += spend.cents }
        }
        return result
    }

    /// Days that have spending, newest first.
    static func dailyTotals(_ spends: [Spend], currency: String, calendar: Calendar = .current) -> [DayTotal] {
        Dictionary(grouping: spends.filter { $0.currency == currency }, by: { calendar.startOfDay(for: $0.date) })
            .map { DayTotal(day: $0.key, cents: $0.value.reduce(0) { $0 + $1.cents }, count: $0.value.count) }
            .sorted { $0.day > $1.day }
    }

    static func years(_ spends: [Spend], now: Date = Date(), calendar: Calendar = .current) -> ClosedRange<Int> {
        let current = calendar.component(.year, from: now)
        let earliest = spends.map { calendar.component(.year, from: $0.date) }.min() ?? current
        return min(earliest, current)...current
    }
}
