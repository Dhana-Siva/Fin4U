import CloudKit
import SwiftUI

/// Test screen for the household sharing mechanism. Not the final household
/// feature: it only proves that a note written on one phone appears on the
/// other. Nothing here touches the real expenses.
struct HouseholdTestView: View {
    @Environment(HouseholdCloud.self) private var cloud
    @Environment(Profile.self) private var profile
    @State private var share: CKShare?
    @State private var showingShare = false
    @State private var draft = ""

    var body: some View {
        List {
            Section {
                if let problem = cloud.accountMessage {
                    Label(problem, systemImage: "exclamationmark.icloud").foregroundStyle(.orange)
                } else if cloud.accountStatus == nil {
                    Label("Checking iCloud...", systemImage: "icloud")
                } else {
                    Label("iCloud is available", systemImage: "checkmark.icloud").foregroundStyle(.green)
                }
            } footer: {
                Text("This is a test of household sharing. It uses a few small notes, not your expenses.")
            }

            if cloud.canUseCloud {
                Section("Household") {
                    if cloud.hasHousehold {
                        Label(cloud.isOwner ? "You started this household" : "You joined a household",
                              systemImage: "house.fill")
                        if cloud.isOwner, !cloud.participantSummary.isEmpty {
                            Text(cloud.participantSummary).font(.footnote).foregroundStyle(.secondary)
                        }
                    }
                    if !cloud.hasHousehold || cloud.isOwner {
                        Button {
                            Task { await invite() }
                        } label: {
                            Label(cloud.hasHousehold ? "Invite or manage people" : "Start a household and invite someone",
                                  systemImage: "person.badge.plus")
                        }
                        .disabled(cloud.isBusy)
                    }
                }

                if cloud.hasHousehold {
                    Section("Send a test note") {
                        HStack {
                            TextField("Type a note", text: $draft)
                            Button("Send") {
                                let text = draft
                                draft = ""
                                Task { await cloud.addNote(text, author: profile.firstName) }
                            }
                            .disabled(draft.trimmingCharacters(in: .whitespaces).isEmpty || cloud.isBusy)
                            .buttonStyle(.borderless)
                        }
                    }

                    Section {
                        if cloud.notes.isEmpty {
                            Text("No notes yet.").foregroundStyle(.secondary)
                        }
                        ForEach(cloud.notes) { note in
                            VStack(alignment: .leading, spacing: 2) {
                                Text(note.text)
                                Text("\(note.author) - \(note.createdAt.formatted(date: .omitted, time: .standard))"
                                     + (note.fromSharedWithMe ? " - shared with you" : ""))
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    } header: {
                        Text("Notes")
                    } footer: {
                        Text("Pull down to refresh. A note sent from the other phone should appear here within a few seconds.")
                    }
                }
            }

            if let message = cloud.message {
                Section { Text(message).font(.footnote).foregroundStyle(.red) }
            }
        }
        .navigationTitle("Household (test)")
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { await cloud.refresh() }
        .task { await cloud.refresh() }
        .overlay { if cloud.isBusy { ProgressView() } }
        .sheet(isPresented: $showingShare, onDismiss: { Task { await cloud.refresh() } }) {
            if let share { CloudSharingView(share: share, container: cloud.container).ignoresSafeArea() }
        }
    }

    private func invite() async {
        do {
            share = try await cloud.prepareShare()
            showingShare = true
        } catch {
            cloud.message = "Couldn't start the household: \(error.localizedDescription)"
        }
    }
}
