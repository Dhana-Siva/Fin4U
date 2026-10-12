import Foundation

/// The short message a shared expense turns into, for pasting into WhatsApp,
/// Messages, email or a Splitwise note. Pure, so the wording and the numbers
/// can be tested.
enum ShareSummary {
    struct Line {
        var name: String
        var cents: Int
        var shares: [(name: String, cents: Int)]
    }

    /// `ownerName` is empty when the user hasn't set a name, in which case the
    /// message is written in the first person ("I paid ... Sam owes me ...").
    static func text(
        merchant: String,
        date: Date,
        currency: String,
        totalCents: Int,
        ownerName: String,
        others: [(name: String, cents: Int)],
        items: [Line],
        taxCents: Int,
        tipCents: Int,
        adjustmentCents: Int
    ) -> String {
        let name = ownerName.trimmingCharacters(in: .whitespaces)
        let subject = name.isEmpty ? "I" : name
        let object = name.isEmpty ? "me" : name
        func money(_ cents: Int) -> String { Money.format(cents, currency: currency) }

        let title = merchant.isEmpty ? "Receipt" : merchant
        var lines = [
            "\(title) - \(date.formatted(.dateTime.month(.abbreviated).day().year()))",
            "\(subject) paid \(money(totalCents)) for this receipt.",
            "",
        ]

        let owing = others.filter { $0.cents != 0 }
        if owing.isEmpty {
            lines.append("Nothing to settle.")
        } else {
            for other in owing { lines.append("\(other.name) owes \(object) \(money(other.cents)).") }
        }

        if !items.isEmpty {
            lines.append("")
            lines.append("How it's split:")
            for item in items {
                let label = item.name.isEmpty ? "Item" : item.name
                let parts = item.shares.filter { $0.cents != 0 }
                    .map { "\($0.name) \(money($0.cents))" }
                    .joined(separator: " / ")
                lines.append("\(label) \(money(item.cents))" + (parts.isEmpty ? "" : "  ->  \(parts)"))
            }
        }

        var extras: [String] = []
        if taxCents != 0 { extras.append("Tax \(money(taxCents))") }
        if tipCents != 0 { extras.append("Tip / service \(money(tipCents))") }
        if adjustmentCents != 0 { extras.append("Not itemized \(money(adjustmentCents))") }
        if !extras.isEmpty {
            lines.append("")
            lines.append(contentsOf: extras)
            lines.append("Tax, tip and anything not itemized are shared in proportion to each person's items.")
        }

        lines.append("")
        lines.append("Sent from Fin4U")
        return lines.joined(separator: "\n")
    }
}

extension ExpenseDraft {
    /// The summary for this (possibly unsaved) expense, from what's on screen now.
    func shareSummary(ownerName: String) -> String {
        let name = ownerName.trimmingCharacters(in: .whitespaces)
        func label(_ id: String, _ fallback: String) -> String {
            id == Participant.me.id ? (name.isEmpty ? "Me" : name) : fallback
        }
        let lines = items.map { item -> ShareSummary.Line in
            let split = plan.resolve(item.split)
            let cents = ExpenseMath.allocate(item.cents, weights: split.map(\.basisPoints))
            return ShareSummary.Line(
                name: item.name,
                cents: item.cents,
                shares: zip(split, cents).map { (name: label($0.0.personID, $0.0.name), cents: $0.1) }
            )
        }
        let others = personTotals
            .filter { $0.id != Participant.me.id }
            .map { (name: $0.name, cents: $0.cents) }
        return ShareSummary.text(
            merchant: merchant, date: date, currency: currency, totalCents: totalCents,
            ownerName: ownerName, others: others, items: lines,
            taxCents: taxCents, tipCents: tipCents, adjustmentCents: effectiveAdjustmentCents
        )
    }
}
