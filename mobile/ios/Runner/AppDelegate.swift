import Flutter
import UIKit
import UserNotifications
import FirebaseCore
import FirebaseMessaging

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  /// Posts a line to the backend's diagnostic sink.
  ///
  /// The Dart side cannot report on native plugin registration - by the time a
  /// channel fails, the only thing Dart knows is that nobody answered. These
  /// probes say whether the native half ever ran.
  static func nativeLog(_ message: String) {
    NSLog(message)
    guard let url = URL(string: "https://api.seaty.hashnate.com/api/v1/public/log") else { return }
    var request = URLRequest(url: url)
    request.httpMethod = "POST"
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.httpBody = try? JSONSerialization.data(
      withJSONObject: ["message": "[native] \(message)"])
    URLSession.shared.dataTask(with: request).resume()
  }

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    FirebaseApp.configure()
    AppDelegate.nativeLog("didFinishLaunching configured=\(FirebaseApp.app() != nil)")
    // Restored: 0b9499d removed this, reverting 93cf5af - the commit that made
    // iOS push work. Without a delegate the plugin has nothing to chain to, so
    // foreground presentation and notification taps are dropped.
    UNUserNotificationCenter.current().delegate = self
    application.registerForRemoteNotifications()

    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  override func application(
    _ application: UIApplication,
    didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
  ) {
    Messaging.messaging().apnsToken = deviceToken
    super.application(application, didRegisterForRemoteNotificationsWithDeviceToken: deviceToken)
  }

  override func application(
    _ application: UIApplication,
    didFailToRegisterForRemoteNotificationsWithError error: Error
  ) {
    let errorMessage = "Failed to register for remote notifications: \(error.localizedDescription)"
    NSLog(errorMessage)

    if let url = URL(string: "https://api.seaty.hashnate.com/api/v1/public/log") {
      var request = URLRequest(url: url)
      request.httpMethod = "POST"
      request.setValue("application/json", forHTTPHeaderField: "Content-Type")
      let json: [String: Any] = ["message": "[ios-native-error] \(errorMessage)"]
      request.httpBody = try? JSONSerialization.data(withJSONObject: json)
      URLSession.shared.dataTask(with: request).resume()
    }

    super.application(application, didFailToRegisterForRemoteNotificationsWithError: error)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    // If this never fires, no plugin is registered and every channel - not just
    // Firebase - answers `channel-error`.
    AppDelegate.nativeLog("didInitializeImplicitFlutterEngine fired")
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    AppDelegate.nativeLog("GeneratedPluginRegistrant.register returned")
  }
}
