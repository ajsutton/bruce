import Foundation

struct HomeAssistantDiscoveryRecord: Equatable, Sendable {
  enum ValidationError: Error, Equatable {
    case missingUUID
  }

  let uuid: String
  let locationName: String
  let version: String?
  let internalURL: URL?
  let externalURL: URL?
  let isOnboarding: Bool
  let invalidURLFields: [String]

  init(
    serviceName: String,
    txt: [String: String],
    resolvedInternalURL: URL? = nil
  ) throws(ValidationError) {
    guard let uuid = Self.nonempty(txt["uuid"]) else {
      throw ValidationError.missingUUID
    }

    let advertisedInternalURL = Self.url(in: txt, field: "internal_url")
    let advertisedExternalURL = Self.url(in: txt, field: "external_url")
    let hasAdvertisedURL = advertisedInternalURL != nil || advertisedExternalURL != nil
    let compatibilityURL = hasAdvertisedURL ? nil : Self.url(in: txt, field: "base_url")

    self.uuid = uuid
    locationName = Self.nonempty(txt["location_name"]) ?? serviceName
    version = Self.nonempty(txt["version"])
    internalURL =
      advertisedInternalURL
      ?? Self.validatedURL(resolvedInternalURL)
      ?? (hasAdvertisedURL ? nil : compatibilityURL)
    externalURL = advertisedExternalURL
    isOnboarding = Self.nonempty(txt["landingpage"])?.lowercased() == "true"
    invalidURLFields = ["base_url", "external_url", "internal_url"].filter {
      Self.hasInvalidURL(in: txt, field: $0)
    }
  }

  var instance: HomeAssistantInstance {
    HomeAssistantInstance(
      id: uuid,
      name: locationName,
      version: version,
      internalURL: internalURL,
      externalURL: externalURL,
      isOnboarding: isOnboarding
    )
  }

  static func hasUsableInternalURL(in txt: [String: String]) -> Bool {
    guard let value = nonempty(txt["internal_url"]), let url = URL(string: value) else {
      return false
    }
    return validatedURL(url) != nil
  }

  private static func nonempty(_ value: String?) -> String? {
    guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else {
      return nil
    }
    return value
  }

  private static func url(in txt: [String: String], field: String) -> URL? {
    guard let value = nonempty(txt[field]), let url = URL(string: value) else {
      return nil
    }
    return validatedURL(url)
  }

  private static func hasInvalidURL(in txt: [String: String], field: String) -> Bool {
    nonempty(txt[field]) != nil && url(in: txt, field: field) == nil
  }

  private static func validatedURL(_ url: URL?) -> URL? {
    guard
      let url,
      var components = URLComponents(url: url, resolvingAgainstBaseURL: false),
      ["http", "https"].contains(components.scheme?.lowercased()),
      components.host?.isEmpty == false,
      components.user == nil,
      components.password == nil,
      components.query == nil,
      components.fragment == nil
    else {
      return nil
    }
    components.scheme = components.scheme?.lowercased()
    return components.url
  }
}
