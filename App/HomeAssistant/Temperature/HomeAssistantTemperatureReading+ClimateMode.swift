extension HomeAssistantTemperatureReading {
  func preferredClimateMode(remembered: ClimateMode?) -> ClimateMode? {
    if powerState == .poweredOn, let active = operatingMode.climateMode,
      availableModes.contains(active)
    {
      return active
    }
    if let remembered, availableModes.contains(remembered) { return remembered }
    return availableModes.contains(.cooling) ? .cooling : availableModes.first
  }
}

extension HomeAssistantTemperatureReading.OperatingMode {
  var climateMode: HomeAssistantTemperatureReading.ClimateMode? {
    switch self {
    case .automatic: .automatic
    case .cooling: .cooling
    case .drying: .drying
    case .fanOnly: .fanOnly
    case .heating: .heating
    case .off, .active, .unavailable: nil
    }
  }
}
