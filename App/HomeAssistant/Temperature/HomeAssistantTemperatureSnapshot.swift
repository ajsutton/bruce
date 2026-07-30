struct HomeAssistantTemperatureSnapshot: Sendable {
  let readings: [HomeAssistantTemperatureReading]
  let unit: String
  let climateMetadata: [String: HomeAssistantClimateMetadata]
}
