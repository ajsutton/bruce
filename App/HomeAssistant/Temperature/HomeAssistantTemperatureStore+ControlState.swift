extension HomeAssistantTemperatureStore {
  func canControl(_ reading: HomeAssistantTemperatureReading) -> Bool {
    controller != nil && isLive && reading.powerState != .unavailable
  }

  var supportsControl: Bool { controller != nil }

  func isAdjustingTarget(entityID: String) -> Bool {
    pendingControls[entityID]?.intent.isTargetValue == true
  }

  func isControlling(entityID: String) -> Bool {
    controllingEntityIDs.contains(entityID)
  }

  func isControllingClimateState(entityID: String) -> Bool {
    isControlling(entityID: entityID) && !isAdjustingTarget(entityID: entityID)
  }
}
