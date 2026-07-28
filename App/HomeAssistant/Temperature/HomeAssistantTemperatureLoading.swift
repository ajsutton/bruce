protocol HomeAssistantTemperatureLoading: Sendable {
  var providesContinuousTemperatureUpdates: Bool { get }

  func temperatureUpdates() -> AsyncThrowingStream<
    HomeAssistantTemperatureUpdate, any Error
  >
}

extension HomeAssistantTemperatureLoading {
  var providesContinuousTemperatureUpdates: Bool { false }
}
