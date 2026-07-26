import Foundation

#if os(iOS)
  import UIKit
#elseif os(macOS)
  import AppKit
#endif

@MainActor
protocol AppIconApplying {
  func apply(_ mode: BruceMode) async throws
}

@MainActor
struct AppIconController: AppIconApplying {
  func apply(_ mode: BruceMode) async throws {
    #if os(iOS)
      let application = UIApplication.shared
      guard application.supportsAlternateIcons else {
        if mode.isFullBruce {
          throw AppIconError.unsupported
        }
        return
      }

      let iconName = mode.isFullBruce ? "AppIconFullBruce" : nil
      guard application.alternateIconName != iconName else {
        return
      }

      try await application.setAlternateIconName(iconName)
    #elseif os(macOS)
      if mode.isFullBruce {
        guard let icon = NSImage(named: "FullBruceDockIcon") else {
          throw AppIconError.missingFullBruceIcon
        }
        NSApplication.shared.applicationIconImage = icon
      } else {
        NSApplication.shared.applicationIconImage = nil
      }
    #endif
  }
}

private enum AppIconError: LocalizedError {
  case missingFullBruceIcon
  case unsupported

  var errorDescription: String? {
    switch self {
    case .missingFullBruceIcon:
      "The Full Bruce app icon is missing."
    case .unsupported:
      "Alternate app icons are unavailable."
    }
  }
}
