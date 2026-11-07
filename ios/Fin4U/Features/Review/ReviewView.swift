import SwiftUI
import SwiftData

/// Check and correct what was read from the receipt, then save it. Also
/// used to edit an already-saved expense (the draft is initialised from it).
struct ReviewView: View {
    @Bindable var draft: ExpenseDraft
    let onClose: () -> Void

    @Environment(\.modelContext) private var context
    @Query(sort: \Person.name) private var people: [Person]
    @Query private var allExpenses: [Expense]
    @State private var addingCard = false
    @State private var newCardName = ""
    @Environment(Profile.self) private var profile
    @Environment(SplitwiseSession.self) private var splitwise
    @AppStorage("splitwiseGroupID") private var splitwiseGroupID = 0
    @State private var splitwiseWorking = false
    @State private var splitwiseError: String?
    @State private var friendPickerFor: Person?
    @State private var postAfterPick = false
    @State private var showingPhoto = false
    @State private var newPersonName = ""

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
                        Text("Compare with your receipt and fix any item below, or type the total yourself. This disappears once the numbers add up.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                        if draft.canUseReceiptTotal {
                            Button("Use the receipt's total (\(Money.format(draft.printedTotalCents, currency: draft.currency)))") {
                                withAnimation { draft.useReceiptTotal() }
                            }
                            .font(.footnote.weight(.semibold))
                            .buttonStyle(.borderless)
                        }
                    }
                }
            }

            sharingSection

            Section("Receipt") {
                TextField("Merchant", text: $draft.merchant)
                DatePicker("Date", selection: $draft.date, displayedComponents: .date)
                Picker("Category", selection: Binding(
                    get: { draft.category },
                    set: { draft.setCategoryForAll($0) }
                )) {
                    ForEach(ExpenseCategory.allCases) { category in
                        Label(category.title, systemImage: category.symbol).tag(category)
                    }
                }
                paidWithRow
            }

            Section {
                ForEach($draft.items) { $item in
                    VStack(alignment: .leading, spacing: 6) {
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
                        HStack(spacing: 8) {
                            categoryChip($item.category)
                            Spacer(minLength: 4)
                            if let other = draft.plan.other, draft.plan.itemize {
                                Toggle("Share", isOn: Binding(
                                    get: { draft.isShared(item) },
                                    set: { draft.setItemShared($0, of: item.id) }
                                ))
                                .labelsHidden()
                                .fixedSize()
                                if draft.isShared(item) {
                                    shareColumn(
                                        name: other.name,
                                        basisPoints: Binding(
                                            get: { draft.otherShare(of: item) },
                                            set: { draft.setOtherShare($0, of: item.id) }
                                        )
                                    )
                                }
                            }
                        }
                        if let other = draft.plan.other {
                            if draft.plan.itemize && !draft.isShared(item) {
                                Text("Not shared -- all yours")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            } else {
                                splitBreakdown(for: item, otherName: other.name)
                            }
                        }
                    }
                }
                .onDelete { draft.items.remove(atOffsets: $0) }

                Button {
                    draft.items.append(DraftItem(name: "", quantity: 1, cents: 0, category: draft.category))
                } label: {
                    Label("Add item", systemImage: "plus.circle.fill")
                }
            } header: {
                Text("Items")
            } footer: {
                if let other = draft.plan.other {
                    Text(draft.plan.itemize
                         ? "Switch on Share for the items you're splitting with \(other.name), then set their %. Tap a category to change it."
                         : "Everything is split the same way. Tap a category to change it.")
                } else {
                    Text("Tap an item's category to change it, for example vitamins on a grocery receipt.")
                }
            }

            Section {
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
                if draft.effectiveAdjustmentCents != 0 {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Not itemized")
                            Text("The part of the total the items above don't explain")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        CentsField(cents: Binding(
                            get: { draft.effectiveAdjustmentCents },
                            set: { draft.setAdjustment($0) }
                        ))
                        .frame(width: 100)
                    }
                }
                HStack {
                    Text("Total").fontWeight(.bold)
                    Spacer()
                    CentsField(cents: Binding(
                        get: { draft.totalCents },
                        set: { draft.setTotal($0) }
                    ))
                    .font(.body.bold())
                    .frame(width: 110)
                }
            } header: {
                Text("Totals")
            } footer: {
                Text("Tap the total to type it exactly as printed on your receipt. Anything the items don't account for is kept as \"Not itemized\".")
            }

            if draft.plan.isShared {
                Section {
                    ForEach(draft.personTotals) { person in
                        totalRow(person.name, person.cents)
                    }
                } header: {
                    Text("Who owes what")
                } footer: {
                    Text("Tax and tip are shared in proportion to each person's items. Only your share counts toward your monthly total.")
                }
            }

            shareSummarySection
            if Config.splitwiseEnabled { splitwiseSection }

            if draft.printedTotalCents > 0 {
                Section {
                    Text("The receipt itself says: subtotal \(Money.format(draft.printedSubtotalCents, currency: draft.currency)), total \(Money.format(draft.printedTotalCents, currency: draft.currency)).")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            } else if draft.existing == nil, draft.receiptImage != nil {
                // Scanned, but no total came back: say so, and where to fix it.
                Section {
                    Label("The receipt's total wasn't recognized. Type it in the Total field above.", systemImage: "info.circle")
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
        .sheet(item: $friendPickerFor) { person in
            FriendPickerView(personName: person.name) { friend in
                person.splitwiseUserID = friend.id
                try? context.save()
                if postAfterPick { Task { await post(to: friend.id) } }
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

    // MARK: Sharing the result

    /// Cards already used on other expenses (and statement imports), so the
    /// same card is always spelled the same way.
    private var knownCards: [String] {
        var cards = Set(allExpenses.map(\.card).filter { !$0.isEmpty })
        if !draft.paidWith.isEmpty { cards.insert(draft.paidWith) }
        return cards.sorted()
    }

    private var paidWithRow: some View {
        Menu {
            Button("None") { draft.paidWith = "" }
            ForEach(knownCards, id: \.self) { card in
                Button(card) { draft.paidWith = card }
            }
            Divider()
            Button("Add a card…") {
                newCardName = ""
                addingCard = true
            }
        } label: {
            HStack {
                Text("Paid with").foregroundStyle(.primary)
                Spacer()
                Text(draft.paidWith.isEmpty ? "Not set" : draft.paidWith)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .alert("Add a card", isPresented: $addingCard) {
            TextField("e.g. American Express, Costco card", text: $newCardName)
            Button("Add") {
                let name = newCardName.trimmingCharacters(in: .whitespacesAndNewlines)
                if !name.isEmpty { draft.paidWith = name }
            }
            Button("Cancel", role: .cancel) {}
        }
    }

    /// A short message with what each person owes, to send from any app.
    @ViewBuilder
    private var shareSummarySection: some View {
        if draft.plan.isShared, draft.plan.other != nil {
            Section {
                ShareLink(item: draft.shareSummary(ownerName: profile.firstName)) {
                    Label("Share summary", systemImage: "square.and.arrow.up")
                }
            } footer: {
                Text("Makes a short message with what each person owes and the items, to send in WhatsApp, Messages or email, or paste into Splitwise.")
            }
        }
    }

    // MARK: Splitwise

    @ViewBuilder
    private var splitwiseSection: some View {
        if draft.plan.isShared, let other = draft.plan.other {
            let person = people.first { $0.id.uuidString == other.id }
            Section {
                if let postedAt = draft.splitwisePostedAt, draft.splitwiseExpenseID != nil {
                    Label("Added to Splitwise on \(postedAt.formatted(date: .abbreviated, time: .omitted))",
                          systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                } else if splitwise.isConnected {
                    Button {
                        Task { await addToSplitwise(person) }
                    } label: {
                        HStack {
                            Label("Add to Splitwise", systemImage: "arrow.up.forward.app")
                            Spacer()
                            if splitwiseWorking { ProgressView() }
                        }
                    }
                    .disabled(splitwiseWorking)
                    if person?.splitwiseUserID != nil {
                        Button("Not \(other.name)? Choose a different friend") {
                            postAfterPick = false
                            friendPickerFor = person
                        }
                        .font(.footnote)
                    }
                } else {
                    Label("Splitwise isn't connected", systemImage: "link.badge.plus")
                        .foregroundStyle(.secondary)
                }
                if let splitwiseError {
                    Text(splitwiseError).font(.footnote).foregroundStyle(.red)
                }
            } header: {
                Text("Splitwise")
            } footer: {
                if draft.splitwiseExpenseID != nil {
                    Text("Changes you make here after this don't update Splitwise.")
                } else if splitwise.isConnected {
                    Text("Saves this expense, then adds it to Splitwise: you paid, and \(other.name) owes their share.")
                } else {
                    Text("Connect Splitwise from your profile (the picture at the top left of the dashboard).")
                }
            }
        }
    }

    private func addToSplitwise(_ person: Person?) async {
        splitwiseError = nil
        guard let person else {
            splitwiseError = "Couldn't find that person on this phone."
            return
        }
        guard let friendID = person.splitwiseUserID else {
            postAfterPick = true
            friendPickerFor = person  // ask once, then post
            return
        }
        await post(to: friendID)
    }

    private func post(to friendID: Int) async {
        splitwiseWorking = true
        defer { splitwiseWorking = false }
        if splitwise.user == nil { await splitwise.refresh() }
        guard let me = splitwise.user else {
            splitwiseError = splitwise.isConnected
                ? "Couldn't confirm your Splitwise account. Check your connection and try again."
                : SplitwiseError.notConnected.localizedDescription
            return
        }
        // Save first (also keeps this screen's draft tied to the saved expense).
        let expense = draft.save(in: context)
        try? context.save()
        do {
            try await SplitwisePoster.post(
                expense, api: splitwise.api, myUserID: me.id,
                myName: profile.firstName.isEmpty ? me.firstName : profile.firstName,
                friendUserID: friendID, groupID: splitwiseGroupID, context: context
            )
            draft.splitwiseExpenseID = expense.splitwiseExpenseID
            draft.splitwisePostedAt = expense.splitwisePostedAt
        } catch SplitwiseError.unauthorized {
            splitwise.disconnect()
            splitwiseError = SplitwiseError.unauthorized.localizedDescription
        } catch {
            splitwiseError = (error as? LocalizedError)?.errorDescription ?? "Couldn't add this to Splitwise."
        }
    }

    // MARK: Sharing

    private var sharingSection: some View {
        Section {
            Toggle(isOn: $draft.plan.isShared.animation()) {
                Label("Shared expense", systemImage: "person.2.fill")
            }

            if draft.plan.isShared {
                ForEach(people) { person in
                    Button {
                        draft.plan.selectOnly(person.participant)
                    } label: {
                        HStack {
                            Text(person.name).foregroundStyle(.primary)
                            Spacer()
                            if draft.plan.isParticipating(person.participant) {
                                Image(systemName: "checkmark").foregroundStyle(Color.accentColor)
                            }
                        }
                    }
                }
                .onDelete(perform: deletePeople)

                HStack {
                    TextField("Add a person", text: $newPersonName)
                        .textInputAutocapitalization(.words)
                        .submitLabel(.done)
                        .onSubmit(addPerson)
                    Button("Add", action: addPerson)
                        .disabled(newPersonName.trimmingCharacters(in: .whitespaces).isEmpty)
                        .buttonStyle(.borderless)
                }

                if let other = draft.plan.other {
                    Picker("Split", selection: Binding(
                        get: { draft.plan.itemize },
                        set: { draft.setItemize($0) }
                    )) {
                        Text("Share all items").tag(false)
                        Text("Itemize").tag(true)
                    }
                    .pickerStyle(.segmented)

                    HStack {
                        Text(draft.plan.itemize ? "\(other.name) pays, when shared" : "\(other.name) pays")
                        Spacer()
                        percentField(Binding(
                            get: { draft.defaultOtherShare },
                            set: { draft.setDefaultOtherShare($0) }
                        ))
                    }

                    Toggle("\(other.name) has paid me back", isOn: $draft.isSettled)
                }
            }
        } footer: {
            if draft.plan.isShared {
                Text(draft.plan.other == nil
                     ? "Tick the person you're splitting with, or add them. Swipe a name to remove it."
                     : (draft.plan.itemize
                        ? "Choose which items are shared below. This % is what each one starts at."
                        : "This % applies to every item."))
            } else {
                Text("Turn on to split this receipt with a roommate or friend.")
            }
        }
    }

    private func addPerson() {
        let name = newPersonName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        newPersonName = ""
        if let existing = people.first(where: { $0.name.caseInsensitiveCompare(name) == .orderedSame }) {
            if !draft.plan.isParticipating(existing.participant) { draft.plan.selectOnly(existing.participant) }
            return
        }
        let person = Person(name: name)
        context.insert(person)
        try? context.save()
        draft.plan.selectOnly(person.participant)
    }

    private func deletePeople(at offsets: IndexSet) {
        for index in offsets {
            let person = people[index]
            if draft.plan.isParticipating(person.participant) { draft.plan.selectOnly(person.participant) }
            context.delete(person)
        }
        try? context.save()
    }

    private func categoryChip(_ category: Binding<ExpenseCategory>) -> some View {
        Menu {
            Picker("Category", selection: category) {
                ForEach(ExpenseCategory.allCases) { option in
                    Label(option.title, systemImage: option.symbol).tag(option)
                }
            }
        } label: {
            chip(category.wrappedValue.title, symbol: category.wrappedValue.symbol, tint: category.wrappedValue.color)
        }
        .buttonStyle(.borderless)
    }

    /// "You $4.00 + Daya $1.00 = $5.00" -- the percentages in actual money.
    private func splitBreakdown(for item: DraftItem, otherName: String) -> some View {
        let amounts = draft.amounts(of: item)
        let money = { Money.format($0, currency: draft.currency) }
        return Text("You \(money(amounts.you)) + \(otherName) \(money(amounts.other)) = \(money(item.cents))")
            .font(.caption)
            .foregroundStyle(.secondary)
            .monospacedDigit()
            .lineLimit(1)
            .minimumScaleFactor(0.8)
    }

    /// "Sam  [ 50.00 ] %" -- who the item is shared with and their share.
    private func shareColumn(name: String, basisPoints: Binding<Int>) -> some View {
        HStack(spacing: 6) {
            Text(name)
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
                .lineLimit(1)
            percentField(basisPoints)
        }
    }

    private func percentField(_ basisPoints: Binding<Int>) -> some View {
        // CentsField works in hundredths, which is exactly basis points:
        // 5000 -> "50.00".
        HStack(spacing: 2) {
            CentsField(cents: Binding(
                get: { basisPoints.wrappedValue },
                set: { basisPoints.wrappedValue = min(max($0, 0), ExpenseMath.whole) }
            ))
            .frame(width: 64)
            .font(.footnote)
            Text("%").font(.footnote).foregroundStyle(.secondary)
        }
        // Without this the "%" is the first thing a tight form row squeezes out.
        .fixedSize()
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Color.accentColor.opacity(0.12), in: Capsule())
    }

    private func chip(_ text: String, symbol: String, tint: Color) -> some View {
        Label(text, systemImage: symbol)
            .font(.caption.weight(.medium))
            .lineLimit(1)
            .foregroundStyle(tint)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(tint.opacity(0.12), in: Capsule())
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
