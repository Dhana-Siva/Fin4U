import SwiftUI
import SwiftData

/// Every transaction from the statement with a tick box and a category menu.
/// Lines matching an already-saved expense start unticked; refunds show as
/// negative amounts. Saving creates one expense per ticked line.
struct StatementReviewView: View {
    @Environment(\.modelContext) private var context

    let statement: ParsedStatement
    @State var lines: [StatementLine]
    let onDone: () -> Void

    private var currency: String { statement.currency.isEmpty ? "USD" : statement.currency }
    private var selected: [StatementLine] { lines.filter(\.include) }
    private var selectedTotal: Int { selected.reduce(0) { $0 + $1.transaction.amountCents } }
    private var skippedPayments: Int { statement.transactions.filter { $0.kind == .payment }.count }

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 4) {
                    Text(StatementImport.sourceLabel(for: statement))
                        .font(.headline)
                    if let period = periodText {
                        Text(period)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    Text("\(selected.count) of \(lines.count) selected · \(Money.format(selectedTotal, currency: currency))")
                        .font(.subheadline.monospacedDigit())
                }
                .padding(.vertical, 4)
            } footer: {
                VStack(alignment: .leading, spacing: 4) {
                    if lines.contains(where: { $0.duplicateOf != nil }) {
                        Text("Unticked lines look like expenses you already saved, so they won't be counted twice. Tick one to add it anyway.")
                    }
                    if skippedPayments > 0 {
                        Text(skippedPayments == 1
                             ? "1 card payment was skipped (it isn't spending)."
                             : "\(skippedPayments) card payments were skipped (they aren't spending).")
                    }
                    ForEach(statement.notes, id: \.self) { note in
                        Label(note, systemImage: "exclamationmark.circle")
                    }
                }
            }

            Section("Transactions") {
                ForEach($lines) { $line in
                    StatementLineRow(line: $line, currency: currency)
                }
            }

            Section {
                HStack {
                    Button("Select all") { setAll(true) }
                    Spacer()
                    Button("Select none") { setAll(false) }
                }
                .buttonStyle(.borderless)
            }
        }
        .navigationTitle("Review statement")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel", action: onDone)
            }
            ToolbarItem(placement: .confirmationAction) {
                Button(selected.count == 1 ? "Add 1" : "Add \(selected.count)") {
                    StatementImport.save(lines, currency: currency, source: StatementImport.sourceLabel(for: statement), in: context)
                    onDone()
                }
                .disabled(selected.isEmpty)
                .bold()
            }
        }
    }

    private var periodText: String? {
        guard let start = ExpenseDraft.parseDate(statement.periodStart),
              let end = ExpenseDraft.parseDate(statement.periodEnd) else { return nil }
        let format = Date.FormatStyle(date: .abbreviated, time: .omitted)
        return "\(start.formatted(format)) – \(end.formatted(format))"
    }

    private func setAll(_ include: Bool) {
        for index in lines.indices { lines[index].include = include }
    }
}

private struct StatementLineRow: View {
    @Binding var line: StatementLine
    let currency: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Button { line.include.toggle() } label: {
                Image(systemName: line.include ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(line.include ? Color.accentColor : .secondary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(line.include ? "Included" : "Not included")

            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline) {
                    Text(line.merchant)
                        .font(.body)
                        .lineLimit(1)
                    Spacer()
                    Text(Money.format(line.transaction.amountCents, currency: currency))
                        .font(.body.monospacedDigit())
                        .foregroundStyle(line.isRefund ? .green : .primary)
                }
                HStack(spacing: 8) {
                    Text(line.date.formatted(.dateTime.month(.abbreviated).day()))
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Menu {
                        Picker("Category", selection: $line.category) {
                            ForEach(ExpenseCategory.allCases) { category in
                                Label(category.title, systemImage: category.symbol).tag(category)
                            }
                        }
                    } label: {
                        Label(line.category.title, systemImage: line.category.symbol)
                            .font(.caption)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(line.category.color.opacity(0.15), in: Capsule())
                            .foregroundStyle(line.category.color)
                    }

                    if line.isRefund {
                        badge("Refund", color: .green)
                    } else if line.transaction.kind == .fee || line.transaction.kind == .interest {
                        badge(line.transaction.kind == .fee ? "Fee" : "Interest", color: .orange)
                    }
                }
                if let duplicate = line.duplicateOf {
                    Text("Already have this: \(duplicate)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .opacity(line.include ? 1 : 0.6)
    }

    private func badge(_ text: String, color: Color) -> some View {
        Text(text)
            .font(.caption2.bold())
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(color.opacity(0.15), in: Capsule())
            .foregroundStyle(color)
    }
}
