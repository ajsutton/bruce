protocol HomeAssistantHomeEnergyLoading: Sendable {
  func loadHomeEnergySnapshot() async throws -> HomeAssistantHomeEnergySnapshot
}
