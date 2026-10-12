import CloudKit
import Foundation
import Observation

/// What the household test screen shows for each note.
struct HouseholdNote: Identifiable, Equatable {
    let id: String
    let text: String
    let author: String
    let createdAt: Date
    /// true when it lives in someone else's iCloud and was shared with us.
    let fromSharedWithMe: Bool

    init?(record: CKRecord, fromSharedWithMe: Bool) {
        guard record.recordType == HouseholdCloud.noteType,
              let text = record["text"] as? String,
              let createdAt = record["createdAt"] as? Date else { return nil }
        self.id = record.recordID.recordName
        self.text = text
        self.author = (record["author"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? "Someone"
        self.createdAt = createdAt
        self.fromSharedWithMe = fromSharedWithMe
    }
}

/// Spike: proves two iCloud accounts can share a small piece of data through
/// CloudKit. The owner creates a zone with a root record and shares it; both
/// people then write "notes" under the root. Everything is in the owner's
/// iCloud; the invited person reads and writes it through the shared database.
@MainActor
@Observable
final class HouseholdCloud {
    static let containerID = "iCloud.com.dhana.fin4u"
    static let zoneName = "Household"
    static let rootType = "Household"
    static let rootName = "household-root"
    static let noteType = "HouseholdNote"

    private(set) var accountStatus: CKAccountStatus?
    private(set) var notes: [HouseholdNote] = []
    private(set) var isBusy = false
    private(set) var isOwner = false
    private(set) var hasHousehold = false
    private(set) var participantSummary = ""
    var message: String?

    @ObservationIgnored let container = CKContainer(identifier: HouseholdCloud.containerID)
    @ObservationIgnored private var ownedZoneID: CKRecordZone.ID?
    /// Where this phone writes new notes: the owner's own zone, or the zone
    /// someone shared with us.
    @ObservationIgnored private var writeTarget: (database: CKDatabase, zoneID: CKRecordZone.ID)?

    var accountMessage: String? {
        switch accountStatus {
        case .available, nil: nil
        case .noAccount: "Not signed in to iCloud. Open Settings and sign in, then come back."
        case .restricted: "iCloud is restricted on this phone."
        case .couldNotDetermine: "Couldn't check iCloud. Try again."
        case .temporarilyUnavailable: "iCloud is temporarily unavailable. Try again in a moment."
        @unknown default: "iCloud isn't available."
        }
    }

    var canUseCloud: Bool { accountStatus == .available }

    // MARK: Refresh

    func refresh() async {
        isBusy = true
        defer { isBusy = false }
        do {
            accountStatus = try await container.accountStatus()
            guard canUseCloud else { return }
            try await loadEverything()
        } catch {
            message = describe(error)
        }
    }

    private func loadEverything() async throws {
        var collected: [HouseholdNote] = []
        writeTarget = nil
        hasHousehold = false
        isOwner = false
        participantSummary = ""

        // 1. A household I own (private database).
        let privateDB = container.privateCloudDatabase
        let ownedZones = try await privateDB.allRecordZones().filter { $0.zoneID.zoneName == Self.zoneName }
        if let zone = ownedZones.first {
            ownedZoneID = zone.zoneID
            writeTarget = (privateDB, zone.zoneID)
            hasHousehold = true
            isOwner = true
            collected += try await notes(in: zone.zoneID, database: privateDB, shared: false)
            if let share = try await fetchShare(zoneID: zone.zoneID, database: privateDB) {
                participantSummary = Self.summary(of: share)
            }
        }

        // 2. A household someone else shared with me (shared database).
        let sharedDB = container.sharedCloudDatabase
        let sharedZones = try await sharedDB.allRecordZones().filter { $0.zoneID.zoneName == Self.zoneName }
        if let zone = sharedZones.first {
            if writeTarget == nil { writeTarget = (sharedDB, zone.zoneID) }
            hasHousehold = true
            collected += try await notes(in: zone.zoneID, database: sharedDB, shared: true)
        }

        notes = collected.sorted { $0.createdAt > $1.createdAt }
    }

    private func notes(in zoneID: CKRecordZone.ID, database: CKDatabase, shared: Bool) async throws -> [HouseholdNote] {
        var result: [HouseholdNote] = []
        var token: CKServerChangeToken?
        var more = true
        while more {
            let changes = try await database.recordZoneChanges(inZoneWith: zoneID, since: token)
            for (_, outcome) in changes.modificationResultsByID {
                if let record = try? outcome.get().record, let note = HouseholdNote(record: record, fromSharedWithMe: shared) {
                    result.append(note)
                }
            }
            token = changes.changeToken
            more = changes.moreComing
        }
        return result
    }

    // MARK: Owner: create the household and its share

    /// Creates the household (a zone with a root record) if needed and returns
    /// the share to invite someone with.
    func prepareShare() async throws -> CKShare {
        let database = container.privateCloudDatabase
        let zoneID: CKRecordZone.ID
        if let existing = ownedZoneID {
            zoneID = existing
        } else {
            let zone = CKRecordZone(zoneName: Self.zoneName)
            _ = try await database.modifyRecordZones(saving: [zone], deleting: [])
            zoneID = zone.zoneID
            ownedZoneID = zoneID
        }

        let rootID = CKRecord.ID(recordName: Self.rootName, zoneID: zoneID)
        let root: CKRecord
        do {
            root = try await database.record(for: rootID)
        } catch let error as CKError where error.code == .unknownItem {
            let fresh = CKRecord(recordType: Self.rootType, recordID: rootID)
            fresh["name"] = "Our household" as CKRecordValue
            root = fresh
        }

        if let existingShare = try await fetchShare(zoneID: zoneID, database: database) {
            return existingShare
        }

        let share = CKShare(rootRecord: root)
        share[CKShare.SystemFieldKey.title] = "Our household on Fin4U" as CKRecordValue
        share.publicPermission = .none  // only people invited by name can join
        _ = try await database.modifyRecords(saving: [root, share], deleting: [])
        writeTarget = (database, zoneID)
        hasHousehold = true
        isOwner = true
        return share
    }

    private func fetchShare(zoneID: CKRecordZone.ID, database: CKDatabase) async throws -> CKShare? {
        let rootID = CKRecord.ID(recordName: Self.rootName, zoneID: zoneID)
        guard let root = try? await database.record(for: rootID), let shareRef = root.share else { return nil }
        return try? await database.record(for: shareRef.recordID) as? CKShare
    }

    // MARK: Write

    func addNote(_ text: String, author: String) async {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        guard let target = writeTarget else {
            message = "Set up a household first (or accept an invitation)."
            return
        }
        isBusy = true
        defer { isBusy = false }
        do {
            let rootID = CKRecord.ID(recordName: Self.rootName, zoneID: target.zoneID)
            let record = CKRecord(recordType: Self.noteType, recordID: CKRecord.ID(recordName: UUID().uuidString, zoneID: target.zoneID))
            record["text"] = trimmed as CKRecordValue
            record["author"] = author as CKRecordValue
            record["createdAt"] = Date() as CKRecordValue
            // The parent link is what puts this note inside the shared tree.
            record.parent = CKRecord.Reference(recordID: rootID, action: .none)
            _ = try await target.database.modifyRecords(saving: [record], deleting: [])
            try await loadEverything()
        } catch {
            message = describe(error)
        }
    }

    // MARK: Accept an invitation

    func accept(_ metadata: CKShare.Metadata) async {
        do {
            _ = try await container.accept(metadata)
            message = "Joined the household."
            await refresh()
        } catch {
            message = describe(error)
        }
    }

    // MARK: Helpers

    static func summary(of share: CKShare) -> String {
        let others = share.participants.filter { $0.role != .owner }
        guard !others.isEmpty else { return "Not shared with anyone yet." }
        return others.map { participant in
            let name = participant.userIdentity.nameComponents
                .map { PersonNameComponentsFormatter().string(from: $0) } ?? "Someone"
            let state: String
            switch participant.acceptanceStatus {
            case .accepted: state = "joined"
            case .pending: state = "invited"
            case .removed: state = "removed"
            case .unknown: state = "unknown"
            @unknown default: state = "unknown"
            }
            return "\(name.isEmpty ? "Someone" : name) (\(state))"
        }.joined(separator: ", ")
    }

    private func describe(_ error: Error) -> String {
        if let ck = error as? CKError {
            switch ck.code {
            case .notAuthenticated: return "Not signed in to iCloud."
            case .networkUnavailable, .networkFailure: return "No connection to iCloud. Try again."
            case .permissionFailure: return "You don't have permission to change this household."
            case .quotaExceeded: return "Your iCloud storage is full."
            default: return "iCloud error \(ck.code.rawValue): \(ck.localizedDescription)"
            }
        }
        return error.localizedDescription
    }
}
