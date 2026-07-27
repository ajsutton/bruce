extension HomeAssistantTemperatureStore {
  func isControlling(entityID: String) -> Bool {
    controllingEntityIDs.contains(entityID)
  }

  func isControllingClimateState(entityID: String) -> Bool {
    isControlling(entityID: entityID) && !isAdjustingTarget(entityID: entityID)
  }
}
