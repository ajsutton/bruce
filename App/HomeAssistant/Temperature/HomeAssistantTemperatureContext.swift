struct HomeAssistantTemperatureContext: Sendable {
  let unit: String
  let climateMetadata: [String: HomeAssistantClimateMetadata]
}
