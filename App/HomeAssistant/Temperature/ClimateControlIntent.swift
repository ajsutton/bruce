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

  func applying(
    to reading: HomeAssistantTemperatureReading
  ) -> HomeAssistantTemperatureReading {
    switch self {
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
    }
  }

  func matches(_ reading: HomeAssistantTemperatureReading) -> Bool {
    switch self {
    case .power(let isOn):
      return reading.powerState == (isOn ? .poweredOn : .off)
    case .mode(let mode):
      return reading.operatingMode == mode.operatingMode
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
