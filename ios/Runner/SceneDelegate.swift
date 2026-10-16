import Flutter
import UIKit

class SceneDelegate: FlutterSceneDelegate {
  override func scene(
    _ scene: UIScene,
    openURLContexts URLContexts: Set<UIOpenURLContext>
  ) {
    super.scene(scene, openURLContexts: URLContexts)
    guard let url = URLContexts.first?.url else { return }
    // Forward to AppDelegate channel if available via NotificationCenter
    NotificationCenter.default.post(
      name: Notification.Name("CentliPendingUri"),
      object: nil,
      userInfo: ["uri": url.absoluteString]
    )
  }
}
