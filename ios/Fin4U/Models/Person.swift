import Foundation
import SwiftData

/// Someone the user splits expenses with (a roommate). Names are typed in
/// once and ticked per receipt; they live only on this phone.
@Model
final class Person {
    var id: UUID
    var name: String
    var createdAt: Date
    /// Which of the owner's Splitwise friends this person is, once linked.
    var splitwiseUserID: Int?

    init(name: String) {
        self.id = UUID()
        self.name = name
        self.createdAt = Date()
    }

    var participant: Participant { Participant(id: id.uuidString, name: name) }
}
