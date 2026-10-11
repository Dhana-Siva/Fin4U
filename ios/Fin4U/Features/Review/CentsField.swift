import SwiftUI

/// A text field that edits an integer-cents amount. Keeps what the user is
/// typing as text (so "12." and "-" are allowed mid-edit) and only commits
/// to `cents` when it parses; unparseable input shows red and leaves the
/// last good value in place.
struct CentsField: View {
    @Binding var cents: Int

    @State private var text = ""
    @State private var isValid = true
    @FocusState private var focused: Bool

    var body: some View {
        TextField("0.00", text: $text)
            .keyboardType(.numbersAndPunctuation)
            .multilineTextAlignment(.trailing)
            .monospacedDigit()
            .foregroundStyle(isValid ? Color.primary : Color.red)
            .focused($focused)
            .onAppear { text = Money.plain(cents) }
            .onChange(of: text) { _, newText in
                if newText.trimmingCharacters(in: .whitespaces).isEmpty {
                    cents = 0
                    isValid = true
                } else if let parsed = Money.parseCents(newText) {
                    cents = parsed
                    isValid = true
                } else {
                    isValid = false
                }
            }
            .onChange(of: focused) { _, isFocused in
                // Tidy "12.5" -> "12.50" once editing ends.
                if !isFocused, isValid { text = Money.plain(cents) }
            }
            .onChange(of: cents) { _, newCents in
                // Changed from outside (not by typing here).
                if !focused { text = Money.plain(newCents) }
            }
    }
}
