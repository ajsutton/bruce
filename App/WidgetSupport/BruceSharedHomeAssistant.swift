import Foundation

enum BruceSharedHomeAssistant {
  private static let sourceKey = "homeAssistantWidgetSource"
  private static let routeKey = "homeAssistantWidgetPreferredRoute"

  static func sourceIdentifier(
    instanceID: String?,
    internalURL: URL?,
    externalURL: URL?
  ) -> String {
    if let instanceID, !instanceID.isEmpty {
      return "instance:\(instanceID)"
    }
    return "urls:"
      + [internalURL, externalURL]
      .compactMap { $0.map(sourceURLIdentifier) }
      .sorted()
      .joined(separator: "|")
  }

  private static func sourceURLIdentifier(_ url: URL) -> String {
    guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
      return url.absoluteString
    }
    components.scheme = components.scheme?.lowercased()
    components.host = components.host?.lowercased()
    return components.string ?? url.absoluteString
  }

  static func storedSourceIdentifier() -> String? {
    BruceSharedContainer.defaults()?.string(forKey: sourceKey)
  }

  static func storeSourceIdentifier(_ sourceIdentifier: String?) {
    let defaults = BruceSharedContainer.defaults()
    if let sourceIdentifier {
      defaults?.set(sourceIdentifier, forKey: sourceKey)
    } else {
      defaults?.removeObject(forKey: sourceKey)
    }
  }

  static func preferredWidgetRoute(for sourceIdentifier: String) -> URL? {
    guard let data = BruceSharedContainer.defaults()?.data(forKey: routeKey),
      let preference = try? JSONDecoder().decode(RoutePreference.self, from: data),
      preference.sourceIdentifier == sourceIdentifier
    else { return nil }
    return preference.route
  }

  static func rememberWidgetRoute(_ route: URL, for sourceIdentifier: String) {
    let preference = RoutePreference(sourceIdentifier: sourceIdentifier, route: route)
    guard let data = try? JSONEncoder().encode(preference) else { return }
    BruceSharedContainer.defaults()?.set(data, forKey: routeKey)
  }

  static func clearWidgetRoute() {
    BruceSharedContainer.defaults()?.removeObject(forKey: routeKey)
  }

  private struct RoutePreference: Codable {
    let sourceIdentifier: String
    let route: URL
  }
}
