enum HomeAssistantTemperatureUpdate: Equatable, Sendable {
  case live([HomeAssistantTemperatureReading])
  case refreshing([HomeAssistantTemperatureReading])
  case reconnecting([HomeAssistantTemperatureReading])
}

extension HomeAssistantTemperatureUpdate {
  var readings: [HomeAssistantTemperatureReading] {
    switch self {
    case .live(let readings), .refreshing(let readings),
      .reconnecting(let readings):
      readings
    }
  }

  var isLive: Bool {
    if case .live = self { return true }
    return false
  }
}
