import Foundation

enum HomeAssistantRedirectPolicy {
  static func allowsRedirect(from originalURL: URL, to redirectedURL: URL) -> Bool {
    guard
      originalURL.scheme?.lowercased() == redirectedURL.scheme?.lowercased(),
      originalURL.host()?.lowercased() == redirectedURL.host()?.lowercased(),
      effectivePort(originalURL) == effectivePort(redirectedURL)
    else {
      return false
    }
    return
      !(originalURL.scheme?.lowercased() == "https"
      && redirectedURL.scheme?.lowercased() == "http")
  }

  private static func effectivePort(_ url: URL) -> Int? {
    url.port ?? (url.scheme?.lowercased() == "https" ? 443 : 80)
  }
}
