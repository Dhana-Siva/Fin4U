import SwiftUI

/// Shown once, before anything can be scanned. Names who receives the data
/// and says what's kept -- with an affirmative action, not just passive
/// text. (Learned the hard way on Amma: Apple wants what's sent, to whom,
/// and the user's permission before it happens.)
struct DisclosureView: View {
    let onAcknowledge: () -> Void

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: "doc.text.viewfinder")
                .font(.system(size: 56))
                .foregroundStyle(.tint)

            Text("How Fin4U reads your receipts")
                .font(.title2.bold())
                .multilineTextAlignment(.center)

            VStack(alignment: .leading, spacing: 14) {
                row("camera.viewfinder",
                    "When you scan a receipt, the photo is sent to Fin4U's server and on to Anthropic, the company behind Claude, the AI that reads it and pulls out the items and prices.")
                row("trash",
                    "The photo isn't stored there. Once the items come back, it's discarded.")
                row("iphone",
                    "Your expenses and a copy of each receipt photo are saved only on this phone.")
            }

            Link("Read the full privacy policy", destination: Config.privacyPolicyURL)
                .font(.footnote)

            Spacer()

            Button(action: onAcknowledge) {
                Text("I Understand, Continue")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
        .padding(24)
    }

    private func row(_ symbol: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: symbol)
                .font(.title3)
                .foregroundStyle(.tint)
                .frame(width: 28)
            Text(text)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
