import SwiftData

/// The one place the personal database is configured.
///
/// `cloudKitDatabase: .none` is deliberate and must stay: the app has an
/// iCloud entitlement (for the shared household), and without this SwiftData
/// would quietly try to sync PERSONAL expenses to the user's iCloud -- which
/// breaks the "personal stays on this phone" promise, and fails to load at
/// all because these models aren't built for iCloud sync.
enum PersonalStore {
    static let models: [any PersistentModel.Type] = [Expense.self, ExpenseItem.self, Person.self]

    static func configuration(inMemory: Bool = false) -> ModelConfiguration {
        ModelConfiguration(isStoredInMemoryOnly: inMemory, cloudKitDatabase: .none)
    }

    static func makeContainer(inMemory: Bool = false) throws -> ModelContainer {
        try ModelContainer(for: Schema(models), configurations: configuration(inMemory: inMemory))
    }
}
