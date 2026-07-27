enum HomeAssistantTemperatureIcon {
  static func systemImageName(for homeAssistantIcon: String?) -> String {
    guard let homeAssistantIcon else {
      return "thermometer.medium"
    }
    let normalizedIcon = homeAssistantIcon.lowercased()

    if normalizedIcon.contains("sofa") {
      return "sofa.fill"
    }
    if normalizedIcon.contains("bed") {
      return "bed.double.fill"
    }
    if normalizedIcon.contains("desk") || normalizedIcon.contains("office") {
      return "desktopcomputer"
    }
    if normalizedIcon.contains("table") || normalizedIcon.contains("dining") {
      return "table.furniture.fill"
    }
    if normalizedIcon.contains("fan") {
      return "fan.fill"
    }
    if normalizedIcon.contains("snowflake") {
      return "snowflake"
    }
    if normalizedIcon.contains("fire") || normalizedIcon.contains("radiator") {
      return "flame.fill"
    }
    if normalizedIcon.contains("water") {
      return "drop.fill"
    }
    return "thermometer.medium"
  }
}
