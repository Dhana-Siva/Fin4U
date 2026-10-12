import SwiftUI
import SwiftData

@main
struct Fin4UApp: App {
    // Its own persisted flag, deliberately not folded into any
    // "onboarding complete" flag: that kind of flag never resets, so anyone
    // who'd already passed it would silently skip a disclosure added later
    // (exactly how Amma's App Store disclosure went unseen by a reviewer).
    @AppStorage("receiptDisclosureAcknowledged") private var acknowledged = false
    @State private var profile = Profile()

    var body: some Scene {
        WindowGroup {
            Group {
                if acknowledged {
                    HomeView()
                } else {
                    DisclosureView { acknowledged = true }
                }
            }
            .environment(profile)
        }
        .modelContainer(for: [Expense.self, ExpenseItem.self, Person.self])
    }
}
