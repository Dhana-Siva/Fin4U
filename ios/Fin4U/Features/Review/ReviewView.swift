import SwiftUI
import SwiftData

/// Check and correct what was read from the receipt, then save it. Also
/// used to edit an already-saved expense (the draft is initialised from it).
struct ReviewView: View {
    @Bindable var draft: ExpenseDraft
    let onClose: () -> Void

    @Environment(\.modelContext) private var context
    @State private var showingPhoto = false

    var body: some View {
        Form {
            if !draft.checks.isEmpty {
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        Label("Something may have been misread", systemImage: "exclamationmark.triangle.fill")
                            .font(.subheadline.bold())
                            .foregroundStyle(.orange)
                        ForEach(draft.checks, id: \.self) { message in
                            Text(message).font(.footnote)
                        }
                        Text("Compare with your receipt and fix any item below. This disappears once the numbers add up.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Section("Receipt") {
                TextField("Merchant", text: $draft.merchant)
                DatePicker("Date", selection: $draft.date, displayedComponents: .date)
                Picker("Category", selection: $draft.category) {
                    ForEach(ExpenseCategory.allCases) { category in
                        Label(category.title, systemImage: category.symbol).tag(category)
                    }
                }
            }

            Section("Items") {
                ForEach($draft.items) { $item in
                    HStack(spacing: 8) {
                        TextField("Item", text: $item.name)
                        if item.quantity > 1 {
                            Text("×\(item.quantity)")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                        CentsField(cents: $item.cents)
                            .frame(width: 84)
                    }
                }
                .onDelete { draft.items.remove(atOffsets: $0) }

                Button {
                    draft.items.append(DraftItem(name: "", quantity: 1, cents: 0))
                } label: {
                    Label("Add item", systemImage: "plus.circle.fill")
                }
            }

            Section("Totals") {
                totalRow("Subtotal", draft.subtotalCents)
                HStack {
                    Text("Tax")
                    Spacer()
                    CentsField(cents: $draft.taxCents).frame(width: 100)
                }
                HStack {
                    Text("Tip / service")
                    Spacer()
                    CentsField(cents: $draft.tipCents).frame(width: 100)
                }
                totalRow("Total", draft.totalCents, bold: true)
            }

            if draft.printedTotalCents > 0 {
                Section {
                    Text("The receipt itself says: subtotal \(Money.format(draft.printedSubtotalCents, currency: draft.currency)), total \(Money.format(draft.printedTotalCents, currency: draft.currency)).")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }

            if !draft.notes.isEmpty {
                Section("Notes") {
                    ForEach(Array(draft.notes.enumerated()), id: \.offset) { _, note in
                        Text(note).font(.footnote)
                    }
                }
            }

            if let data = draft.receiptImage, let image = UIImage(data: data) {
                Section("Receipt photo") {
                    Button { showingPhoto = true } label: {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFit()
                            .frame(maxHeight: 180)
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .navigationTitle(draft.existing == nil ? "Review" : "Edit expense")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel", action: onClose)
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") {
                    draft.save(in: context)
                    try? context.save()
                    onClose()
                }
                .disabled(!draft.canSave)
            }
        }
        .sheet(isPresented: $showingPhoto) {
            if let data = draft.receiptImage, let image = UIImage(data: data) {
                NavigationStack {
                    ScrollView([.horizontal, .vertical]) {
                        Image(uiImage: image).resizable().scaledToFit()
                    }
                    .navigationTitle("Receipt photo")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Done") { showingPhoto = false }
                        }
                    }
                }
            }
        }
    }

    private func totalRow(_ title: String, _ cents: Int, bold: Bool = false) -> some View {
        HStack {
            Text(title).fontWeight(bold ? .bold : .regular)
            Spacer()
            Text(Money.format(cents, currency: draft.currency))
                .fontWeight(bold ? .bold : .regular)
                .monospacedDigit()
        }
    }
}
