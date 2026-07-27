enum HomeAssistantTemperatureConnection: Equatable {
  case disconnected
  case connecting
  case connected(HomeAssistantCredentials)
  case unavailable
}
