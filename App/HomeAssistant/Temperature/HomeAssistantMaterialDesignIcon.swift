import CoreText
import Foundation
import OSLog

enum HomeAssistantMaterialDesignIcon {
  static let fontName = "MaterialDesignIcons"

  private static let logger = Logger(
    subsystem: Bundle.main.bundleIdentifier ?? "net.symphonious.bruce",
    category: "MaterialDesignIcons"
  )

  static func prepare() {
    resources.prepare()
  }

  static func glyph(for identifier: String?) -> String? {
    guard let identifier, identifier.lowercased().hasPrefix("mdi:") else {
      return nil
    }
    let name = String(identifier.dropFirst(4)).lowercased()
    guard
      let resources = resources.value,
      let codepoint = resources.codepoints[name],
      let scalar = UnicodeScalar(codepoint)
    else {
      return nil
    }
    return String(Character(scalar))
  }

  private static let resources = ResourceStorage()

  private static func loadResources() -> Resources? {
    guard
      let url = Bundle.main.url(forResource: "codepoints", withExtension: "json"),
      let data = try? Data(contentsOf: url),
      let codepoints = try? JSONDecoder().decode([String: UInt32].self, from: data)
    else {
      logger.error("Couldn’t load the bundled Material Design Icons index.")
      return nil
    }

    guard
      let fontURL = Bundle.main.url(
        forResource: "materialdesignicons-webfont",
        withExtension: "ttf"
      )
    else {
      logger.error("Couldn’t find the bundled Material Design Icons font.")
      return nil
    }

    var registrationError: Unmanaged<CFError>?
    if CTFontManagerRegisterFontsForURL(fontURL as CFURL, .process, &registrationError) {
      return Resources(codepoints: codepoints)
    }

    let font = CTFontCreateWithName(fontName as CFString, 24, nil)
    let registeredName = CTFontCopyPostScriptName(font) as String
    if registeredName == fontName {
      return Resources(codepoints: codepoints)
    }
    logger.error("Couldn’t register the bundled Material Design Icons font.")
    return nil
  }
}

extension HomeAssistantMaterialDesignIcon {
  fileprivate struct Resources: Sendable {
    let codepoints: [String: UInt32]
  }

  fileprivate final class ResourceStorage: @unchecked Sendable {
    private let lock = NSLock()
    private var storedValue: Resources?
    private var didPrepare = false

    var value: Resources? {
      lock.withLock { storedValue }
    }

    func prepare() {
      lock.withLock {
        guard !didPrepare else {
          return
        }
        didPrepare = true
        storedValue = HomeAssistantMaterialDesignIcon.loadResources()
      }
    }
  }
}
