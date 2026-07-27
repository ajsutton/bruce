protocol HomeAssistantTemperatureLoading: Sendable {
  func temperatureUpdates() -> AsyncThrowingStream<
    HomeAssistantTemperatureUpdate, any Error
  >
}
