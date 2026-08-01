struct TemperatureCopy {
  private let copy: BruceCopy

  init(mode: BruceMode) {
    copy = BruceCopy(mode: mode)
  }

  var navigationTitle: String { text(.navigationTitle) }
  var controlFailedTitle: String { text(.controlFailedTitle) }
  var dismiss: String { text(.dismiss) }
  var temperaturesUnavailable: String { text(.temperaturesUnavailable) }
  var noCurrentTemperatures: String { text(.noCurrentTemperatures) }
  var noCurrentTemperaturesDescription: String { text(.noCurrentTemperaturesDescription) }
  var manage: String { text(.manage) }
  var tryAgain: String { text(.tryAgain) }
  var removingConnection: String { text(.removingConnection) }
  var live: String { text(.live) }
  var lastChecked: String { text(.lastChecked) }
  var checkingConnection: String { text(.checkingConnection) }
  var updating: String { text(.updating) }
  var lastKnown: String { text(.lastKnown) }
  var lastKnownUpdating: String { text(.lastKnownUpdating) }
  var updatingTemperatures: String { text(.updatingTemperatures) }
  var current: String { text(.current) }
  var target: String { text(.target) }
  var average: String { text(.average) }
  var houseAverage: String { text(.houseAverage) }
  var mode: String { text(.mode) }
  var powerOn: String { text(.powerOn) }
  var powerOff: String { text(.powerOff) }
  var unavailable: String { text(.unavailable) }
  var inProgress: String { text(.inProgress) }
  var automatic: String { text(.automatic) }
  var automaticAccessibility: String { text(.automaticAccessibility) }
  var cooling: String { text(.cooling) }
  var coolingAccessibility: String { text(.coolingAccessibility) }
  var drying: String { text(.drying) }
  var dryingAccessibility: String { text(.dryingAccessibility) }
  var fanOnly: String { text(.fanOnly) }
  var fanOnlyAccessibility: String { text(.fanOnlyAccessibility) }
  var heating: String { text(.heating) }
  var heatingAccessibility: String { text(.heatingAccessibility) }
  var powerOnAccessibility: String { text(.powerOnAccessibility) }
  var powerOffAccessibility: String { text(.powerOffAccessibility) }
  var unavailableAccessibility: String { text(.unavailableAccessibility) }
  var all: String { text(.all) }
  var none: String { text(.none) }
  var allClimateZones: String { text(.allClimateZones) }
  var noClimateZones: String { text(.noClimateZones) }

  func climatePreset(named name: String) -> String {
    text(.namedClimatePreset).replacingOccurrences(of: "%@", with: name)
  }

  func problem(_ problem: HomeAssistantTemperatureStore.Problem) -> String {
    switch problem {
    case .connectionUnavailable:
      text(.connectionUnavailable)
    case .reconnecting:
      text(.reconnecting)
    case .signInRequired:
      text(.signInRequired)
    case .invalidResponse:
      text(.invalidResponse)
    case .other:
      text(.otherProblem)
    }
  }

  func controlFailed(name: String) -> String {
    text(.controlFailed).replacingOccurrences(of: "%@", with: name)
  }

  func updating(name: String) -> String {
    text(.updatingName).replacingOccurrences(of: "%@", with: name)
  }

  func lastKnown(_ value: String) -> String {
    "\(lastKnown). \(value)"
  }

  func turnOff(name: String) -> String {
    text(.turnOff).replacingOccurrences(of: "%@", with: name)
  }

  func turnOn(name: String) -> String {
    text(.turnOn).replacingOccurrences(of: "%@", with: name)
  }

  func powerUnavailable(name: String) -> String {
    text(.powerUnavailable).replacingOccurrences(of: "%@", with: name)
  }

  func mode(name: String) -> String {
    text(.namedMode).replacingOccurrences(of: "%@", with: name)
  }

  func increaseTarget(name: String) -> String {
    text(.increaseTarget).replacingOccurrences(of: "%@", with: name)
  }

  func decreaseTarget(name: String) -> String {
    text(.decreaseTarget).replacingOccurrences(of: "%@", with: name)
  }

  func target(name: String) -> String {
    text(.namedTarget).replacingOccurrences(of: "%@", with: name)
  }

  func accessibilityValue(
    isUpdating: Bool,
    power: String,
    current: String,
    target: String
  ) -> String {
    let key: Key = isUpdating ? .updatingAccessibilityValue : .accessibilityValue
    return text(key)
      .replacingOccurrences(of: "%1$@", with: power)
      .replacingOccurrences(of: "%2$@", with: current)
      .replacingOccurrences(of: "%3$@", with: target)
  }

  private func text(_ key: Key) -> String {
    copy.text(key.entry)
  }
}

extension TemperatureCopy {
  fileprivate enum Key {
    case navigationTitle, controlFailedTitle, dismiss, temperaturesUnavailable
    case noCurrentTemperatures, noCurrentTemperaturesDescription, manage, tryAgain
    case removingConnection, live, lastChecked, checkingConnection, updating, lastKnown
    case lastKnownUpdating
    case updatingTemperatures, current, target, average, houseAverage, mode
    case powerOn, powerOff, unavailable, inProgress, automatic, cooling, drying, fanOnly, heating
    case automaticAccessibility, coolingAccessibility, dryingAccessibility
    case fanOnlyAccessibility, heatingAccessibility, powerOnAccessibility
    case powerOffAccessibility, unavailableAccessibility
    case connectionUnavailable, reconnecting, signInRequired, invalidResponse, otherProblem
    case controlFailed, updatingName, turnOff, turnOn, powerUnavailable, namedMode
    case increaseTarget, decreaseTarget, namedTarget, accessibilityValue
    case updatingAccessibilityValue
    case all, none, allClimateZones, noClimateZones, namedClimatePreset

    var entry: BruceCopy.Entry {
      switch self {
      case .navigationTitle: .localized("temperature.navigationTitle")
      case .controlFailedTitle: .localized("temperature.controlFailedTitle")
      case .dismiss: .localized("temperature.dismiss")
      case .temperaturesUnavailable:
        .localized("temperature.temperaturesUnavailable")
      case .noCurrentTemperatures:
        .localized("temperature.noCurrentTemperatures")
      case .noCurrentTemperaturesDescription:
        .localized("temperature.noCurrentTemperaturesDescription")
      case .manage: .localized("temperature.manage")
      case .tryAgain:
        .localized("temperature.tryAgain")
      case .removingConnection:
        .localized("temperature.removingConnection")
      case .live: .localized("temperature.live")
      case .lastChecked: .localized("temperature.lastChecked")
      case .checkingConnection:
        .localized("temperature.checkingConnection")
      case .updating: .localized("temperature.updating")
      case .lastKnown: .localized("temperature.lastKnown")
      case .lastKnownUpdating: .localized("temperature.lastKnownUpdating")
      case .updatingTemperatures:
        .localized("temperature.updatingTemperatures")
      case .current: .localized("temperature.current")
      case .target: .localized("temperature.target")
      case .average: .localized("temperature.average")
      case .houseAverage: .localized("temperature.houseAverage")
      case .mode: .localized("temperature.mode")
      case .powerOn: .localized("temperature.powerOn")
      case .powerOff: .localized("temperature.powerOff")
      case .unavailable: .localized("temperature.unavailable")
      case .inProgress: .localized("temperature.inProgress")
      case .automatic: .localized("temperature.automatic")
      case .automaticAccessibility:
        .localized("temperature.automaticAccessibility")
      case .cooling: .localized("temperature.cooling")
      case .coolingAccessibility:
        .localized("temperature.coolingAccessibility")
      case .drying: .localized("temperature.drying")
      case .dryingAccessibility:
        .localized("temperature.dryingAccessibility")
      case .fanOnly: .localized("temperature.fanOnly")
      case .fanOnlyAccessibility:
        .localized("temperature.fanOnlyAccessibility")
      case .heating: .localized("temperature.heating")
      case .heatingAccessibility:
        .localized("temperature.heatingAccessibility")
      case .powerOnAccessibility:
        .localized("temperature.powerOnAccessibility")
      case .powerOffAccessibility:
        .localized("temperature.powerOffAccessibility")
      case .unavailableAccessibility:
        .localized("temperature.unavailableAccessibility")
      case .connectionUnavailable:
        .localized("temperature.connectionUnavailable")
      case .reconnecting:
        .localized("temperature.reconnecting")
      case .signInRequired:
        .localized("temperature.signInRequired")
      case .invalidResponse:
        .localized("temperature.invalidResponse")
      case .otherProblem:
        .localized("temperature.otherProblem")
      case .controlFailed:
        .localized("temperature.controlFailed")
      case .updatingName: .localized("temperature.updatingName")
      case .turnOff: .localized("temperature.turnOff")
      case .turnOn: .localized("temperature.turnOn")
      case .powerUnavailable:
        .localized("temperature.powerUnavailable")
      case .namedMode: .localized("temperature.namedMode")
      case .increaseTarget: .localized("temperature.increaseTarget")
      case .decreaseTarget: .localized("temperature.decreaseTarget")
      case .namedTarget: .localized("temperature.namedTarget")
      case .accessibilityValue:
        .localized("temperature.accessibilityValue")
      case .updatingAccessibilityValue:
        .localized("temperature.updatingAccessibilityValue")
      case .all: .localized("temperature.all")
      case .none: .localized("temperature.none")
      case .allClimateZones: .localized("temperature.allClimateZones")
      case .noClimateZones: .localized("temperature.noClimateZones")
      case .namedClimatePreset: .localized("temperature.namedClimatePreset")
      }
    }
  }
}
