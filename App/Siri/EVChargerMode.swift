import AppIntents

enum EVChargerMode: String, AppEnum {
  case off
  case smart
  case charging

  static let typeDisplayRepresentation: TypeDisplayRepresentation = "siri.mode.type"
  static let caseDisplayRepresentations: [Self: DisplayRepresentation] = [
    .off: "siri.mode.off",
    .smart: DisplayRepresentation(
      title: "siri.mode.smart",
      synonyms: ["siri.mode.smart.synonym", "siri.mode.automatic.synonym"]),
    .charging: DisplayRepresentation(title: "siri.mode.on", synonyms: ["siri.mode.on.synonym"]),
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
