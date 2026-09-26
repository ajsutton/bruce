import AppIntents

enum EVChargerMode: String, AppEnum {
  case off
  case smart
  case charging

  static let typeDisplayRepresentation: TypeDisplayRepresentation = "EV charger mode"
  static let caseDisplayRepresentations: [Self: DisplayRepresentation] = [
    .off: "Off",
    .smart: DisplayRepresentation(
      title: "Smart Charging",
      synonyms: ["Smart", "Automatic"]),
    .charging: DisplayRepresentation(title: "On", synonyms: ["Charge now"]),
  ]

  var homeAssistantMode: HomeAssistantEVChargingMode {
    switch self {
    case .off: .off
    case .smart: .smart
    case .charging: .charging
    }
  }

  init(_ mode: HomeAssistantEVChargingMode) {
    switch mode {
    case .off: self = .off
    case .smart: self = .smart
    case .charging: self = .charging
    }
  }

}
