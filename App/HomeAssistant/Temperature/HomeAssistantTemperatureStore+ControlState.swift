extension HomeAssistantTemperatureStore {
  func canControl(_ reading: HomeAssistantTemperatureReading) -> Bool {
    canControlDuringPreset(reading)
      && presetControlTask == nil
      && presetTransaction == nil
  }

  func canControlDuringPreset(_ reading: HomeAssistantTemperatureReading) -> Bool {
    controller != nil && isLive && reading.powerState != .unavailable
  }

  var supportsControl: Bool { controller != nil }

  func isAdjusting(entityID: String) -> Bool {
    pendingControls[entityID]?.intent.isAdjustment == true
  }

  func isControlling(entityID: String) -> Bool {
    controllingEntityIDs.contains(entityID)
  }

  func isControllingClimateState(entityID: String) -> Bool {
    isControlling(entityID: entityID) && !isAdjusting(entityID: entityID)
  }
}
