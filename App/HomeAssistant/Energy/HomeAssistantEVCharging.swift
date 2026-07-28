protocol HomeAssistantEVCharging: Sendable {
  func loadEVChargingMode() async throws -> HomeAssistantEVChargingMode
  func setEVChargingMode(
    _ mode: HomeAssistantEVChargingMode
  ) async throws -> HomeAssistantEVChargingMode
}
