enum HomeAssistantEVChargingMode: String, CaseIterable, Hashable, Sendable {
  case off = "Off"
  case smart = "Smart Charging"
  case charging = "On"

  var title: String {
    switch self {
    case .off:
      "Off"
    case .smart:
      "Battery"
    case .charging:
      "On"
    }
  }

  func description(for bruceMode: BruceMode) -> String {
    if bruceMode.isFullBruce {
      return fullBruceDescription
    }
    return neutralDescription
  }

  var neutralDescription: String {
    switch self {
    case .off:
      "Off"
    case .smart:
      "Charges when the home battery has enough power"
    case .charging:
      "Charges regardless of home battery level"
    }
  }

  private var fullBruceDescription: String {
    switch self {
    case .off:
      "Off. Charger’s parked up."
    case .smart:
      "Charges when the home battery’s got enough in the tank"
    case .charging:
      "Charges regardless of the home battery. Give it the berries."
    }
  }
}
