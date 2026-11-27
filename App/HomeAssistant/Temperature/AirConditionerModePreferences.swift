import Foundation

@MainActor
struct AirConditionerModePreferences {
  private let defaults: UserDefaults?
  private(set) var server: HomeAssistantServerIdentity?

  init(defaults: UserDefaults? = nil) {
    self.defaults = defaults
  }

  mutating func selectServer(
    _ server: HomeAssistantServerIdentity?
  ) -> [String: HomeAssistantTemperatureReading.ClimateMode]? {
    guard self.server != server else { return nil }
    self.server = server
    guard let server else { return [:] }
    let values = defaults?.dictionary(forKey: storageKey(for: server)) as? [String: String] ?? [:]
    return values.compactMapValues(HomeAssistantTemperatureReading.ClimateMode.init(rawValue:))
  }

  func save(_ modes: [String: HomeAssistantTemperatureReading.ClimateMode]) {
    guard let server else { return }
    defaults?.set(modes.mapValues(\.rawValue), forKey: storageKey(for: server))
  }

  private func storageKey(for server: HomeAssistantServerIdentity) -> String {
    switch server {
    case .instance(let id):
      return "climate.lastModes.instance.\(id)"
    case .endpoints(let internalURL, let externalURL):
      let local = internalURL?.absoluteString ?? ""
      let remote = externalURL?.absoluteString ?? ""
      return
        "climate.lastModes.endpoints.\(local.utf8.count):\(local)\(remote.utf8.count):\(remote)"
    }
  }
}
