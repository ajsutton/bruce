enum HomeAssistantTemperatureUpdate: Equatable, Sendable {
  case live([HomeAssistantTemperatureReading])
  case reconnecting([HomeAssistantTemperatureReading])
}
