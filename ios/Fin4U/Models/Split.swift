import Foundation

/// Someone an expense can be split with. `id` is "me" for the phone's owner
/// or a `Person`'s UUID string; `name` is copied in so a saved expense still
/// reads correctly after that person is renamed or removed.
struct Participant: Codable, Equatable, Hashable, Identifiable {
    var id: String
    var name: String

    static let me = Participant(id: "me", name: "You")
}

/// One person's slice of an item. `basisPoints` is hundredths of a percent
/// (10_000 == 100%), so shares are exact integers like the money is.
struct ShareEntry: Codable, Equatable, Identifiable {
    var personID: String
    var name: String
    var basisPoints: Int

    var id: String { personID }
}

/// One line of an expense as the split maths sees it.
struct LineInput {
    var cents: Int
    var category: ExpenseCategory
    /// nil means "use the receipt's default split".
    var override: [ShareEntry]?
}

struct PersonTotal: Equatable, Identifiable {
    var id: String
    var name: String
    var cents: Int
}

/// How an expense is shared. Not shared == everything is 100% yours.
struct SplitPlan: Equatable {
    var isShared = false
    /// The other people, not including "me".
    var participants: [Participant] = []
    /// A hand-edited receipt-wide split; nil means an even split.
    var customDefault: [ShareEntry]?

    var everyone: [Participant] { [.me] + participants }

    var meOnly: [ShareEntry] {
        [ShareEntry(personID: Participant.me.id, name: Participant.me.name, basisPoints: ExpenseMath.whole)]
    }

    var defaultSplit: [ShareEntry] {
        guard isShared else { return meOnly }
        if let custom = customDefault, let normalized = ExpenseMath.normalize(custom, allowed: everyone) {
            return normalized
        }
        return ExpenseMath.equalSplit(everyone)
    }

    /// The split that actually applies to a line with this override.
    func resolve(_ override: [ShareEntry]?) -> [ShareEntry] {
        guard isShared else { return meOnly }
        if let override, let normalized = ExpenseMath.normalize(override, allowed: everyone) {
            return normalized
        }
        return defaultSplit
    }

    func isParticipating(_ person: Participant) -> Bool {
        participants.contains { $0.id == person.id }
    }

    /// Adding or removing someone invalidates a hand-edited default (it would
    /// either leave the newcomer at 0% or keep a stale share), so go back to
    /// an even split.
    mutating func toggle(_ person: Participant) {
        if let index = participants.firstIndex(where: { $0.id == person.id }) {
            participants.remove(at: index)
        } else {
            participants.append(person)
        }
        customDefault = nil
    }
}

/// Stored with a shared expense so it can be reopened and edited.
struct SplitSnapshot: Codable {
    var participants: [Participant]
    var defaultSplit: [ShareEntry]?
}

enum ExpenseMath {
    /// 100% in basis points.
    static let whole = 10_000

    /// Divides `total` across `weights` in whole cents so the parts add up to
    /// exactly `total` (largest-remainder method). Negative totals (discounts)
    /// are split the same way, mirrored.
    static func allocate(_ total: Int, weights: [Int]) -> [Int] {
        guard !weights.isEmpty else { return [] }
        let clean = weights.map { max($0, 0) }
        let sum = clean.reduce(0, +)
        var parts = Array(repeating: 0, count: clean.count)
        if sum == 0 {
            parts[0] = total
            return parts
        }
        let magnitude = abs(total)
        let sign = total < 0 ? -1 : 1
        parts = clean.map { $0 * magnitude / sum }
        var leftover = magnitude - parts.reduce(0, +)
        let byRemainder = clean.indices.sorted { a, b in
            let ra = clean[a] * magnitude % sum
            let rb = clean[b] * magnitude % sum
            return ra != rb ? ra > rb : a < b
        }
        var cursor = 0
        while leftover > 0 {
            parts[byRemainder[cursor % byRemainder.count]] += 1
            leftover -= 1
            cursor += 1
        }
        return parts.map { $0 * sign }
    }

    static func equalSplit(_ people: [Participant]) -> [ShareEntry] {
        let basisPoints = allocate(whole, weights: Array(repeating: 1, count: people.count))
        return zip(people, basisPoints).map { ShareEntry(personID: $0.id, name: $0.name, basisPoints: $1) }
    }

    /// Keeps only the allowed people with a positive share and rescales them
    /// to 100%. nil if nobody is left.
    static func normalize(_ split: [ShareEntry], allowed: [Participant]) -> [ShareEntry]? {
        let ids = Set(allowed.map(\.id))
        let kept = split.filter { ids.contains($0.personID) && $0.basisPoints > 0 }
        guard !kept.isEmpty else { return nil }
        let sum = kept.reduce(0) { $0 + $1.basisPoints }
        if sum == whole { return kept }
        let rescaled = allocate(whole, weights: kept.map(\.basisPoints))
        return zip(kept, rescaled).map { ShareEntry(personID: $0.personID, name: $0.name, basisPoints: $1) }
    }

    /// What each person owes for the whole receipt: their share of every item,
    /// plus tax and tip in proportion to how much of the items they carry.
    /// The totals always add up to subtotal + tax + tip exactly.
    static func personTotals(plan: SplitPlan, lines: [LineInput], taxCents: Int, tipCents: Int) -> [PersonTotal] {
        let order = plan.isShared ? plan.everyone : [Participant.me]
        var subtotals: [String: Int] = [:]
        for line in lines {
            let split = plan.resolve(line.override)
            let shares = allocate(line.cents, weights: split.map(\.basisPoints))
            for (entry, cents) in zip(split, shares) { subtotals[entry.personID, default: 0] += cents }
        }

        var weights = order.map { subtotals[$0.id] ?? 0 }
        if weights.allSatisfy({ $0 <= 0 }) {
            // No items to go by (or they cancel out): follow the default split.
            let fallback = Dictionary(uniqueKeysWithValues: plan.defaultSplit.map { ($0.personID, $0.basisPoints) })
            weights = order.map { fallback[$0.id] ?? 0 }
        }
        let overhead = allocate(taxCents + tipCents, weights: weights)

        return order.enumerated().map { index, person in
            PersonTotal(id: person.id, name: person.name, cents: (subtotals[person.id] ?? 0) + overhead[index])
        }
    }

    /// One person's total broken down by category, so a shared Shoprite trip
    /// still lands partly in Groceries and partly in Health. Tax and tip are
    /// spread over their categories in proportion to what they spent in each.
    static func categoryTotals(
        for personID: String,
        plan: SplitPlan,
        lines: [LineInput],
        taxCents: Int,
        tipCents: Int,
        receiptCategory: ExpenseCategory
    ) -> [ExpenseCategory: Int] {
        var mine: [Int] = []
        for line in lines {
            let split = plan.resolve(line.override)
            let shares = allocate(line.cents, weights: split.map(\.basisPoints))
            mine.append(zip(split, shares).first { $0.0.personID == personID }?.1 ?? 0)
        }

        let total = personTotals(plan: plan, lines: lines, taxCents: taxCents, tipCents: tipCents)
            .first { $0.id == personID }?.cents ?? 0
        let overhead = total - mine.reduce(0, +)

        var result: [ExpenseCategory: Int] = [:]
        for (line, cents) in zip(lines, mine) { result[line.category, default: 0] += cents }

        if mine.contains(where: { $0 > 0 }) {
            let extra = allocate(overhead, weights: mine)
            for (line, cents) in zip(lines, extra) { result[line.category, default: 0] += cents }
        } else if overhead != 0 {
            result[receiptCategory, default: 0] += overhead
        }
        return result.filter { $0.value != 0 }
    }

    static func percentText(_ basisPoints: Int) -> String {
        basisPoints % 100 == 0
            ? "\(basisPoints / 100)%"
            : String(format: "%.2f%%", Double(basisPoints) / 100)
    }

    /// "Even · You, Sam" or "You 60% · Sam 40%".
    static func describe(_ split: [ShareEntry]) -> String {
        guard let first = split.first else { return "" }
        let isEven = split.count > 1 && split.allSatisfy { abs($0.basisPoints - first.basisPoints) <= 1 }
        if isEven { return "Even · " + split.map(\.name).joined(separator: ", ") }
        if split.count == 1 { return "\(first.name) only" }
        return split.map { "\($0.name) \(percentText($0.basisPoints))" }.joined(separator: " · ")
    }
}
