import Foundation
import SwiftData

enum SplitwisePosterError: LocalizedError, Equatable {
    case notShared
    case alreadyAdded

    var errorDescription: String? {
        switch self {
        case .notShared: "This expense isn't shared with anyone, so there's nothing to add to Splitwise."
        case .alreadyAdded: "This expense is already in Splitwise."
        }
    }
}

/// Turns a saved, shared expense into a Splitwise expense. You paid the whole
/// bill; everyone owes their share (tax and tip included), exactly as the
/// "Who owes what" totals on the review screen show.
@MainActor
enum SplitwisePoster {
    /// Builds the form fields without sending anything -- the testable half.
    static func fields(
        for expense: Expense,
        myUserID: Int,
        myName: String,
        friendUserID: Int,
        groupID: Int
    ) throws -> [String: String] {
        let plan = expense.splitPlan
        guard plan.isShared, plan.other != nil else { throw SplitwisePosterError.notShared }

        let totals = Dictionary(uniqueKeysWithValues: expense.personTotals.map { ($0.id, $0.cents) })
        let myCents = totals[Participant.me.id] ?? 0
        let otherID = plan.other!.id
        let theirCents = totals[otherID] ?? 0

        let shares = [
            SplitwiseShare(userID: myUserID, paidCents: expense.totalCents, owedCents: myCents),
            SplitwiseShare(userID: friendUserID, paidCents: 0, owedCents: theirCents),
        ]

        func displayName(_ id: String, _ fallback: String) -> String { id == Participant.me.id ? myName : fallback }
        let items = expense.sortedItems.map { item in
            let split = plan.resolve(item.splitOverride)
            let cents = ExpenseMath.allocate(item.lineTotalCents, weights: split.map(\.basisPoints))
            return (
                name: item.name,
                cents: item.lineTotalCents,
                shares: zip(split, cents).map { (name: displayName($0.0.personID, $0.0.name), cents: $0.1) }
            )
        }
        let details = SplitwisePayload.details(
            merchant: expense.merchant, items: items,
            taxCents: expense.taxCents, tipCents: expense.tipCents, currency: expense.currency
        )

        return try SplitwisePayload.fields(
            description: expense.merchant, date: expense.date, currency: expense.currency,
            totalCents: expense.totalCents, groupID: groupID, shares: shares, details: details
        )
    }

    /// Sends the expense and, only if Splitwise accepts it, records that it
    /// was added so it can't be added twice.
    static func post(
        _ expense: Expense,
        api: SplitwiseAPI,
        myUserID: Int,
        myName: String,
        friendUserID: Int,
        groupID: Int,
        context: ModelContext
    ) async throws {
        if expense.splitwiseExpenseID != nil { throw SplitwisePosterError.alreadyAdded }
        let fields = try fields(for: expense, myUserID: myUserID, myName: myName, friendUserID: friendUserID, groupID: groupID)
        let id = try await api.createExpense(fields: fields)
        expense.splitwiseExpenseID = id
        expense.splitwisePostedAt = Date()
        try? context.save()
    }
}
