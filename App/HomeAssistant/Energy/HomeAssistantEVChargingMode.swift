enum HomeAssistantEVChargingMode: String, CaseIterable, Hashable, Sendable {
  case off = "Off"
  case smart = "Smart Charging"
  case charging = "On"

  var title: String {
    switch self {
    case .off:
      "Off"
    case .smart:
      "Smart"
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
      "Charges when the home has energy to spare"
    case .charging:
      "Charges regardless of home battery level"
    }
  }

  private var fullBruceDescription: String {
    switch self {
    case .off:
      "Off. Charger’s knocked off."
    case .smart:
      "Charges when the house has juice to burn. Too easy."
    case .charging:
      "Charges regardless of the home battery. Flat chat."
    }
  }
}
