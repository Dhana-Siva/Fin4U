import SwiftUI

/// Shown before the first Splitwise connection. It has its own persisted flag
/// (`splitwiseConsentAcknowledged`), separate from the receipt disclosure's:
/// an existing "I've seen the disclosure" flag would silently skip a new data
/// flow for everyone who'd already passed it.
struct SplitwiseConsentView: View {
    let onAgree: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Image(systemName: "arrow.triangle.2.circlepath")
                        .font(.system(size: 44))
                        .foregroundStyle(Color.accentColor)
                    Text("Sharing with Splitwise")
                        .font(.title2.bold())

                    point("paperplane.fill",
                          "Only when you tap \"Add to Splitwise\" on a shared expense, Fin4U sends Splitwise: the merchant, date, total, how it's split, the list of items with prices, and the Splitwise friend you picked.")
                    point("iphone",
                          "It goes straight from your phone to Splitwise, under your own Splitwise account. Receipt photos are never sent.")
                    point("lock.shield.fill",
                          "Fin4U's server only helps you sign in. It never sees your expenses, and the sign-in token is kept on this phone, not on the server.")
                    point("xmark.circle.fill",
                          "You can disconnect any time from your profile. Expenses already in Splitwise stay there, and Splitwise's own privacy policy applies to them.")

                    HStack(spacing: 16) {
                        Link("Fin4U privacy policy", destination: Config.privacyPolicyURL)
                        Link("Splitwise privacy", destination: URL(string: "https://www.splitwise.com/privacy")!)
                    }
                    .font(.footnote)
                }
                .padding(24)
            }
            .safeAreaInset(edge: .bottom) {
                VStack(spacing: 10) {
                    Button {
                        onAgree()
                        dismiss()
                    } label: {
                        Text("Agree and connect").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    Button("Not now") { dismiss() }
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 12)
                .background(.bar)
            }
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private func point(_ symbol: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: symbol)
                .frame(width: 26)
                .foregroundStyle(Color.accentColor)
            Text(text)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }
}
