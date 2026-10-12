import Foundation

struct SplitwiseUser: Decodable, Equatable, Identifiable {
    let id: Int
    let firstName: String
    let lastName: String?
    let email: String?

    var displayName: String {
        [firstName, lastName].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " ")
    }
}

struct SplitwiseGroup: Decodable, Equatable, Identifiable {
    let id: Int
    let name: String
}

/// Decoded with `.convertFromSnakeCase`. Only what the app uses.
struct SplitwiseCurrentUserResponse: Decodable { let user: SplitwiseUser }
struct SplitwiseFriendsResponse: Decodable { let friends: [SplitwiseUser] }
struct SplitwiseGroupsResponse: Decodable { let groups: [SplitwiseGroup] }

/// The reply to create_expense. Splitwise reports problems in `errors` with a
/// 200 status, so success is "errors is empty", not "status is 200".
struct SplitwiseCreateExpenseResponse: Decodable {
    struct Created: Decodable { let id: Int }
    let expenses: [Created]?
    let errors: SplitwiseErrors?
}

/// `errors` arrives as `{}` when fine, or a dictionary / array / string of messages.
struct SplitwiseErrors: Decodable {
    let messages: [String]

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let dict = try? container.decode([String: [String]].self) {
            messages = dict.values.flatMap { $0 }
        } else if let dict = try? container.decode([String: String].self) {
            messages = Array(dict.values)
        } else if let array = try? container.decode([String].self) {
            messages = array
        } else if let text = try? container.decode(String.self) {
            messages = [text]
        } else {
            messages = []
        }
    }
}
