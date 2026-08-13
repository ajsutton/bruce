enum HomeAssistantTemperatureUpdate: Equatable, Sendable {
  case live([HomeAssistantTemperatureReading])
  case refreshing([HomeAssistantTemperatureReading])
  case reconnecting([HomeAssistantTemperatureReading])
  case unavailable([HomeAssistantTemperatureReading])
}

extension HomeAssistantTemperatureUpdate {
  var readings: [HomeAssistantTemperatureReading] {
    switch self {
    case .live(let readings), .refreshing(let readings),
      .reconnecting(let readings), .unavailable(let readings):
      readings
    }
  }

  var isLive: Bool {
    if case .live = self { return true }
    return false
  }
}

extension HomeAssistantTemperatureUpdate: HomeAssistantBufferedUpdate {
  var isLiveUpdate: Bool { isLive }

  func preservingControlTransition(from dropped: Self) -> Self? {
    guard case .live(let readings) = self else { return nil }
    return switch dropped {
    case .refreshing: .refreshing(readings)
    case .reconnecting: .reconnecting(readings)
    case .unavailable: .unavailable(readings)
    case .live: nil
    }
  }
}
