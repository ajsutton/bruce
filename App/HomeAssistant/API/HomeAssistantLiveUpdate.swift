enum HomeAssistantLiveUpdate<Value: Sendable>: Sendable {
  case live(Value)
  case refreshing(Value)
  case reconnecting(Value)
  case unavailable(Value)
}

extension HomeAssistantLiveUpdate: Equatable where Value: Equatable {}
