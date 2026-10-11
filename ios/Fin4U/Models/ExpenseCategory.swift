import SwiftUI

/// Raw values match the backend's `CATEGORIES` list exactly -- the model is
/// constrained to these by an enum in the output schema.
enum ExpenseCategory: String, CaseIterable, Identifiable {
    case groceries, dining, transport, shopping, health, entertainment, utilities, other

    var id: String { rawValue }

    /// Unknown values fall back to `.other` rather than failing to load.
    init(raw: String) {
        self = ExpenseCategory(rawValue: raw) ?? .other
    }

    var title: String { rawValue.capitalized }

    var symbol: String {
        switch self {
        case .groceries: "cart.fill"
        case .dining: "fork.knife"
        case .transport: "car.fill"
        case .shopping: "bag.fill"
        case .health: "cross.case.fill"
        case .entertainment: "popcorn.fill"
        case .utilities: "bolt.fill"
        case .other: "tag.fill"
        }
    }

    var color: Color {
        switch self {
        case .groceries: .green
        case .dining: .orange
        case .transport: .blue
        case .shopping: .pink
        case .health: .red
        case .entertainment: .purple
        case .utilities: .yellow
        case .other: .gray
        }
    }
}
