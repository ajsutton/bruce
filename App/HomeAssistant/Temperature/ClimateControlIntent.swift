import Foundation

struct PendingClimateControl {
  let intent: ClimateControlIntent
  let sequence: Int
  var isAccepted: Bool
}

enum ClimateControlIntent {
  case power(isOn: Bool)
  case mode(HomeAssistantTemperatureReading.ClimateMode)
  case targetValue(Double)
  case opening(value: Double, entityID: String)

  var isAdjustment: Bool {
    switch self {
    case .targetValue, .opening: true
    case .power, .mode: false
    }
  }

  func canReplaceAdjustment(_ other: Self) -> Bool {
    switch (self, other) {
    case (.targetValue, .targetValue), (.opening, .opening): true
    default: false
    }
  }

  func applying(
    to reading: HomeAssistantTemperatureReading
  ) -> HomeAssistantTemperatureReading {
    guard reading.powerState != .unavailable else { return reading }
    return switch self {
    case .power(isOn: true):
      reading.replacingClimateState(powerState: .poweredOn, operatingMode: .active)
    case .power(isOn: false):
      reading.replacingClimateState(powerState: .off, operatingMode: .off)
    case .mode(let mode):
      reading.replacingClimateState(
        powerState: .poweredOn,
        operatingMode: mode.operatingMode
      )
    case .targetValue(let value):
      reading.replacingTargetValue(value)
    case .opening(let value, let entityID):
      if let opening = reading.opening, opening.entityID == entityID {
        reading.replacingOpening(opening.replacingValue(value))
          .replacingClimateState(
            powerState: value == 0 ? .off : .poweredOn,
            operatingMode: value == 0 ? .off : .active
          )
      } else {
        reading
      }
    }
  }

  func matches(_ reading: HomeAssistantTemperatureReading) -> Bool {
    switch self {
    case .power(let isOn):
      return reading.powerState == (isOn ? .poweredOn : .off)
    case .mode(let mode):
      return reading.operatingMode == mode.operatingMode
    case .opening(let value, let entityID):
      guard let opening = reading.opening, opening.entityID == entityID, opening.isAvailable,
        let currentValue = opening.value
      else { return false }
      // AirTouch uses a zero-position command to switch off; the reported opening
      // can retain the minimum damper position while the zone is off.
      if value == 0 { return reading.powerState == .off }
      return abs(currentValue - value) < 0.000_1 && reading.powerState == .poweredOn
    case .targetValue(let value):
      guard let targetValue = reading.targetValue else {
        return false
      }
      return abs(targetValue - value) < 0.000_1
    }
  }
}

extension HomeAssistantTemperatureReading.ClimateMode {
  fileprivate var operatingMode: HomeAssistantTemperatureReading.OperatingMode {
    switch self {
    case .automatic:
      .automatic
    case .cooling:
      .cooling
    case .drying:
      .drying
    case .fanOnly:
      .fanOnly
    case .heating:
      .heating
    }
  }
}
