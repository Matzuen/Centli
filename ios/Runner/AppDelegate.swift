import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  private var pendingIntakeChannel: FlutterMethodChannel?
  private var queuedUri: String?

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    if let url = launchOptions?[.url] as? URL {
      queuedUri = url.absoluteString
    }
    NotificationCenter.default.addObserver(
      self,
      selector: #selector(onPendingUri(_:)),
      name: Notification.Name("CentliPendingUri"),
      object: nil
    )
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  @objc private func onPendingUri(_ note: Notification) {
    guard let uri = note.userInfo?["uri"] as? String else { return }
    deliverUri(uri)
  }

  private func deliverUri(_ uri: String) {
    let payload: [String: Any?] = ["kind": "uri", "uri": uri]
    if let ch = pendingIntakeChannel {
      ch.invokeMethod("pending_intake", arguments: payload)
    } else {
      queuedUri = uri
    }
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    let messenger = engineBridge.applicationRegistrar.messenger()
    pendingIntakeChannel = FlutterMethodChannel(
      name: "centli/notification_capture",
      binaryMessenger: messenger
    )
    if let uri = queuedUri {
      queuedUri = nil
      deliverUri(uri)
    }
  }

  override func application(
    _ app: UIApplication,
    open url: URL,
    options: [UIApplication.OpenURLOptionsKey: Any] = [:]
  ) -> Bool {
    deliverUri(url.absoluteString)
    return true
  }
}
