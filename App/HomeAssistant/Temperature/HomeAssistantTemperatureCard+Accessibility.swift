import Foundation

extension HomeAssistantTemperatureCard {
  var powerStateLabel: String {
    let copy = TemperatureCopy(mode: mode)
    switch reading.powerState {
    case .poweredOn:
      return copy.powerOn
    case .off:
      return copy.powerOff
    case .unavailable:
      return copy.unavailable
    }
  }

  var powerAccessibilityLabel: String {
    let copy = TemperatureCopy(mode: mode)
    if isControlling {
      return copy.updating(name: reading.name)
    }
    switch reading.powerState {
    case .poweredOn:
      return copy.turnOff(name: reading.name)
    case .off:
      return copy.turnOn(name: reading.name)
    case .unavailable:
      return copy.powerUnavailable(name: reading.name)
    }
  }

  var powerAccessibilityValue: String {
    let copy = TemperatureCopy(mode: mode)
    let currentValue = temperatureAccessibilityValue(
      reading.value,
      fractionLength: 1
    )
    let targetValue =
      reading.targetValue.map {
        temperatureAccessibilityValue(
          $0,
          fractionLength: targetValueFractionLength
        )
      } ?? copy.unavailable
    let value = copy.accessibilityValue(
      isUpdating: isControlling,
      power: powerStateLabel,
      current: currentValue,
      target: targetValue
    )
    return isLastKnown ? copy.lastKnown(value) : value
  }

  func temperatureAccessibilityValue(
    _ value: Double,
    fractionLength: Int
  ) -> String {
    let formattedValue = value.formatted(
      .number.precision(.fractionLength(fractionLength))
    )
    return "\(formattedValue)\(reading.unit ?? "")"
  }
}
