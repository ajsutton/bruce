enum HomeAssistantEVChargingActivity: Equatable, Sendable {
  case unavailable
  case notPluggedIn
  case connected
  case waitingForVehicle
  case charging(powerWatts: Double?)
  case complete
  case paused(reason: PauseReason?)
  case switchedOff

  enum PauseReason: Equatable, Sendable {
    case electricityPrice
    case homeBattery
  }

  var isCharging: Bool {
    if case .charging = self {
      return true
    }
    return false
  }
}
