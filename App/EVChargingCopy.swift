import Foundation

struct EVChargingCopy {
  private let copy: BruceCopy

  init(mode: BruceMode) {
    copy = BruceCopy(mode: mode)
  }

  var carCharger: String { text(.carCharger) }
  var chargingMode: String { text(.chargingMode) }
  var manage: String { text(.manage) }
  var refresh: String { text(.refresh) }
  var checkCurrentMode: String { text(.checkCurrentMode) }
  var chargerStatus: String { text(.chargerStatus) }
  var checkingChargerStatus: String { text(.checkingChargerStatus) }
  var chargerStatusUnavailable: String { text(.chargerStatusUnavailable) }
  var checkingMode: String { text(.checkingMode) }
  var modeUnavailable: String { text(.modeUnavailable) }
  var changingChargingMode: String { text(.changingChargingMode) }
  var checkingChargingMode: String { text(.checkingChargingMode) }
  var requestedMode: String { text(.requestedMode) }
  var updating: String { text(.updating) }
  var checkingCurrentMode: String { text(.checkingCurrentMode) }
  var lastKnown: String { text(.lastKnown) }
  var unavailable: String { text(.unavailable) }
  var notPluggedIn: String { text(.notPluggedIn) }
  var connectedReady: String { text(.connectedReady) }
  var waitingForVehicle: String { text(.waitingForVehicle) }
  var chargeComplete: String { text(.chargeComplete) }
  var chargingPaused: String { text(.chargingPaused) }
  var chargingSwitchedOff: String { text(.chargingSwitchedOff) }
  var pausedForPrice: String { text(.pausedForPrice) }
  var pausedForBattery: String { text(.pausedForBattery) }

  func lastKnown(_ value: String) -> String {
    "\(lastKnown): \(value)"
  }

  func charging(powerWatts: Double?, locale: Locale) -> String {
    guard let powerWatts else {
      return text(.charging)
    }
    let kilowatts = powerWatts / 1_000
    let power =
      "\(kilowatts.formatted(.number.locale(locale).precision(.fractionLength(1)))) kW"
    return text(.chargingWithPower).replacingOccurrences(of: "%@", with: power)
  }

  func chargingModeTitle(_ mode: HomeAssistantEVChargingMode) -> String {
    switch mode {
    case .off: text(.chargingModeOff)
    case .smart: text(.chargingModeSmart)
    case .charging: text(.chargingModeOn)
    }
  }

  func chargingModeAccessibilityLabel(_ mode: HomeAssistantEVChargingMode) -> String {
    switch mode {
    case .off: text(.chargingModeOffAccessibility)
    case .smart: text(.chargingModeSmartAccessibility)
    case .charging: text(.chargingModeOnAccessibility)
    }
  }

  func chargingModeDescription(_ mode: HomeAssistantEVChargingMode) -> String {
    switch mode {
    case .off: text(.chargingModeOffDescription)
    case .smart: text(.chargingModeSmartDescription)
    case .charging: text(.chargingModeOnDescription)
    }
  }

  func problem(_ problem: HomeAssistantEVChargingStore.Problem) -> String {
    switch problem {
    case .connectionNeedsManagement: text(.connectionNeedsManagement)
    case .connectionUnavailable: text(.connectionUnavailable)
    case .signInRequired: text(.signInRequired)
    case .invalidResponse: text(.invalidResponse)
    case .updateFailed: text(.updateFailed)
    case .updateTimedOut: text(.updateTimedOut)
    }
  }

  private func text(_ key: Key) -> String {
    copy.text(key.entry)
  }
}

extension EVChargingCopy {
  fileprivate enum Key {
    case carCharger, chargingMode, manage, refresh, checkCurrentMode
    case chargerStatus, checkingChargerStatus, chargerStatusUnavailable
    case checkingMode, modeUnavailable, changingChargingMode, checkingChargingMode
    case requestedMode, updating, checkingCurrentMode, lastKnown, unavailable
    case notPluggedIn, connectedReady, waitingForVehicle, charging, chargingWithPower
    case chargeComplete, chargingPaused, chargingSwitchedOff, pausedForPrice, pausedForBattery
    case chargingModeOff, chargingModeSmart, chargingModeOn
    case chargingModeOffAccessibility, chargingModeSmartAccessibility
    case chargingModeOnAccessibility
    case chargingModeOffDescription, chargingModeSmartDescription, chargingModeOnDescription
    case connectionNeedsManagement, connectionUnavailable, signInRequired
    case invalidResponse, updateFailed, updateTimedOut

    var entry: BruceCopy.Entry {
      switch self {
      case .carCharger: .localized("evCharging.carCharger")
      case .chargingMode: .localized("evCharging.chargingMode")
      case .manage: .localized("evCharging.manage")
      case .refresh: .localized("evCharging.refresh")
      case .checkCurrentMode: .localized("evCharging.checkCurrentMode")
      case .chargerStatus: .localized("evCharging.chargerStatus")
      case .checkingChargerStatus:
        .localized("evCharging.checkingChargerStatus")
      case .chargerStatusUnavailable:
        .localized("evCharging.chargerStatusUnavailable")
      case .checkingMode: .localized("evCharging.checkingMode")
      case .modeUnavailable: .localized("evCharging.modeUnavailable")
      case .changingChargingMode:
        .localized("evCharging.changingChargingMode")
      case .checkingChargingMode:
        .localized("evCharging.checkingChargingMode")
      case .requestedMode: .localized("evCharging.requestedMode")
      case .updating: .localized("evCharging.updating")
      case .checkingCurrentMode: .localized("evCharging.checkingCurrentMode")
      case .lastKnown: .localized("evCharging.lastKnown")
      case .unavailable: .localized("evCharging.unavailable")
      case .notPluggedIn:
        .localized("evCharging.notPluggedIn")
      case .connectedReady:
        .localized("evCharging.connectedReady")
      case .waitingForVehicle:
        .localized("evCharging.waitingForVehicle")
      case .charging: .localized("evCharging.charging")
      case .chargingWithPower:
        .localized("evCharging.chargingWithPower")
      case .chargeComplete: .localized("evCharging.chargeComplete")
      case .chargingPaused: .localized("evCharging.chargingPaused")
      case .chargingSwitchedOff:
        .localized("evCharging.chargingSwitchedOff")
      case .pausedForPrice:
        .localized("evCharging.pausedForPrice")
      case .pausedForBattery:
        .localized("evCharging.pausedForBattery")
      case .chargingModeOff: .localized("evCharging.chargingModeOff")
      case .chargingModeSmart: .localized("evCharging.chargingModeSmart")
      case .chargingModeOn: .localized("evCharging.chargingModeOn")
      case .chargingModeOffAccessibility:
        .localized("evCharging.chargingModeOffAccessibility")
      case .chargingModeSmartAccessibility:
        .localized("evCharging.chargingModeSmartAccessibility")
      case .chargingModeOnAccessibility:
        .localized("evCharging.chargingModeOnAccessibility")
      case .chargingModeOffDescription:
        .localized("evCharging.chargingModeOffDescription")
      case .chargingModeSmartDescription:
        .localized("evCharging.chargingModeSmartDescription")
      case .chargingModeOnDescription:
        .localized("evCharging.chargingModeOnDescription")
      case .connectionNeedsManagement:
        .localized("evCharging.connectionNeedsManagement")
      case .connectionUnavailable:
        .localized("evCharging.connectionUnavailable")
      case .signInRequired:
        .localized("evCharging.signInRequired")
      case .invalidResponse:
        .localized("evCharging.invalidResponse")
      case .updateFailed:
        .localized("evCharging.updateFailed")
      case .updateTimedOut:
        .localized("evCharging.updateTimedOut")
      }
    }
  }
}
