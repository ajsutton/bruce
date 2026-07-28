protocol HomeAssistantEVCharging: Sendable {
  func loadEVChargingMode() async throws -> HomeAssistantEVChargingMode
  func loadEVChargingSnapshot() async throws -> HomeAssistantEVChargingSnapshot
  func setEVChargingMode(
    _ mode: HomeAssistantEVChargingMode
  ) async throws -> HomeAssistantEVChargingMode
}

extension HomeAssistantEVCharging {
  func loadEVChargingSnapshot() async throws -> HomeAssistantEVChargingSnapshot {
    HomeAssistantEVChargingSnapshot(
      mode: try await loadEVChargingMode(),
      activity: .unavailable
    )
  }
}
