import Foundation

enum BruceSharedContainer {
  static let releaseSuiteName = "group.net.symphonious.bruce"
  static let debugSuiteName = "group.net.symphonious.bruce.debug"

  static func suiteName(bundleIdentifier: String? = Bundle.main.bundleIdentifier) -> String {
    bundleIdentifier?.contains(".debug") == true
      ? debugSuiteName
      : releaseSuiteName
  }

  static func defaults(bundleIdentifier: String? = Bundle.main.bundleIdentifier) -> UserDefaults? {
    UserDefaults(suiteName: suiteName(bundleIdentifier: bundleIdentifier))
  }

  static func url(bundleIdentifier: String? = Bundle.main.bundleIdentifier) -> URL? {
    FileManager.default.containerURL(
      forSecurityApplicationGroupIdentifier: suiteName(bundleIdentifier: bundleIdentifier)
    )
  }
}
