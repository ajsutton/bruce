enum HomeAssistantLiveUpdate<Value: Sendable>: Sendable {
  case live(Value)
  case refreshing(Value)
  case reconnecting(Value)
}

extension HomeAssistantLiveUpdate: Equatable where Value: Equatable {}
