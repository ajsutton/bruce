import Foundation

extension HomeAssistantTemperatureCard {
  var powerStateLabel: String {
    switch reading.powerState {
    case .poweredOn:
      "On"
    case .off:
      "Off"
    case .unavailable:
      "Unavailable"
    }
  }

  var powerAccessibilityLabel: String {
    if isControlling {
      return "Updating \(reading.name)"
    }
    switch reading.powerState {
    case .poweredOn:
      return "Turn off \(reading.name)"
    case .off:
      return "Turn on \(reading.name)"
    case .unavailable:
      return "\(reading.name) power unavailable"
    }
  }

  var powerAccessibilityValue: String {
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
      } ?? "Unavailable"
    let progress = isControlling ? "Updating. " : ""
    return "\(progress)\(powerStateLabel). Current \(currentValue). Target \(targetValue)"
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
