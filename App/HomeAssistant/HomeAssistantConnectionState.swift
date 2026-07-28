enum HomeAssistantConnectionState: Equatable {
  case disconnected
  case connecting
  case connected(HomeAssistantCredentials)
  case unavailable
}
