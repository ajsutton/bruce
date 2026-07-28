struct HomeAssistantEVChargingSnapshot: Equatable, Sendable {
  let mode: HomeAssistantEVChargingMode
  let activity: HomeAssistantEVChargingActivity
}
