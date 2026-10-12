import CloudKit
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
    @State private var splitwise = SplitwiseSession()
    @State private var household = HouseholdCloud()
    private let personalContainer: ModelContainer = {
        do { return try PersonalStore.makeContainer() }
        catch { fatalError("Couldn't open the personal database: \(error)") }
    }()
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

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
            .environment(splitwise)
            .environment(household)
            .onReceive(NotificationCenter.default.publisher(for: .householdInvitationOpened)) { note in
                if let metadata = note.object as? CKShare.Metadata {
                    Task { await household.accept(metadata) }
                }
            }
            .task { if Config.splitwiseEnabled { await splitwise.refresh() } }
        }
        .modelContainer(personalContainer)
    }
}
