#if os(iOS)
  import UIKit

  @MainActor
  final class BruceSceneDelegate: NSObject, UIWindowSceneDelegate, ObservableObject {
    @Published private(set) var manageConnectionRequestID = 0

    func scene(
      _ scene: UIScene,
      willConnectTo session: UISceneSession,
      options connectionOptions: UIScene.ConnectionOptions
    ) {
      handle(connectionOptions.shortcutItem)
    }

    func windowScene(
      _ windowScene: UIWindowScene,
      performActionFor shortcutItem: UIApplicationShortcutItem
    ) async -> Bool {
      handle(shortcutItem)
    }

    @discardableResult
    func handle(_ shortcutItem: UIApplicationShortcutItem?) -> Bool {
      guard shortcutItem?.type == BruceQuickAction.manageConnectionType else {
        return false
      }
      manageConnectionRequestID += 1
      return true
    }
  }
#endif
