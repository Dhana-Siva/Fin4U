import Foundation
import SwiftData

/// Someone the user splits expenses with (a roommate). Names are typed in
/// once and ticked per receipt; they live only on this phone.
@Model
final class Person {
    var id: UUID
    var name: String
    var createdAt: Date

    init(name: String) {
        self.id = UUID()
        self.name = name
        self.createdAt = Date()
    }

    var participant: Participant { Participant(id: id.uuidString, name: name) }
}
