import CloudKit
import SwiftUI
import UIKit

extension Notification.Name {
    /// Posted with a `CKShare.Metadata` when the user opens a household invitation.
    static let householdInvitationOpened = Notification.Name("householdInvitationOpened")
}

/// iOS hands iCloud share invitations to the scene delegate. SwiftUI apps
/// reach it through an app delegate that names this class.
final class SceneDelegate: UIResponder, UIWindowSceneDelegate {
    func windowScene(_ windowScene: UIWindowScene, userDidAcceptCloudKitShareWith metadata: CKShare.Metadata) {
        NotificationCenter.default.post(name: .householdInvitationOpened, object: metadata)
    }
}

final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        configurationForConnecting connectingSceneSession: UISceneSession,
        options: UIScene.ConnectionOptions
    ) -> UISceneConfiguration {
        let configuration = UISceneConfiguration(name: nil, sessionRole: connectingSceneSession.role)
        configuration.delegateClass = SceneDelegate.self
        return configuration
    }
}

/// Wraps Apple's standard "invite people" sheet.
struct CloudSharingView: UIViewControllerRepresentable {
    let share: CKShare
    let container: CKContainer

    func makeUIViewController(context: Context) -> UICloudSharingController {
        let controller = UICloudSharingController(share: share, container: container)
        controller.availablePermissions = [.allowReadWrite, .allowPrivate]
        return controller
    }

    func updateUIViewController(_ controller: UICloudSharingController, context: Context) {}
}
