protocol HomeAssistantClimateControlling: Sendable {
  func setPower(entityID: String, isOn: Bool) async throws
  func setTargetValue(_ value: Double, entityID: String) async throws
  func setMode(
    _ mode: HomeAssistantTemperatureReading.ClimateMode,
    entityID: String
  ) async throws
}
