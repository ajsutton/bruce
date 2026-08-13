struct HomeAssistantEVChargingStream: HomeAssistantEVCharging {
  let providesContinuousUpdates = true

  private let states: any HomeAssistantStateLoading
  private let controller: any HomeAssistantEVCharging

  init(
    states: any HomeAssistantStateLoading,
    controller: any HomeAssistantEVCharging
  ) {
    self.states = states
    self.controller = controller
  }

  func evChargingUpdates() -> HomeAssistantEVChargingUpdateStream {
    HomeAssistantEVChargingUpdateStream { continuation in
      let task = Task {
        do {
          var lastUpdate: HomeAssistantEVChargingUpdate?
          let stateUpdates = await states.stateUpdates()
          defer { stateUpdates.cancel() }
          for try await stateUpdate in stateUpdates {
            try Task.checkCancellation()
            guard
              let update = Self.evChargingUpdate(
                from: stateUpdate,
                lastUpdate: lastUpdate
              )
            else { continue }
            guard update != lastUpdate else { continue }
            lastUpdate = update
            continuation.yield(update)
          }
          continuation.finish()
        } catch is CancellationError {
          continuation.finish()
        } catch {
          continuation.finish(throwing: error)
        }
      }
      continuation.onTermination = { _ in
        task.cancel()
      }
    }
  }

  func loadEVChargingMode() async throws -> HomeAssistantEVChargingMode {
    try await controller.loadEVChargingMode()
  }

  func loadEVChargingSnapshot() async throws -> HomeAssistantEVChargingSnapshot {
    try await controller.loadEVChargingSnapshot()
  }

  func setEVChargingMode(
    _ mode: HomeAssistantEVChargingMode
  ) async throws -> HomeAssistantEVChargingMode {
    try await controller.setEVChargingMode(mode)
  }

  private static func evChargingUpdate(
    from update: HomeAssistantStateUpdate,
    lastUpdate: HomeAssistantEVChargingUpdate?
  ) -> HomeAssistantEVChargingUpdate? {
    switch update.phase {
    case .live:
      switch HomeAssistantEVChargingSnapshot.modeEntityDiscovery(in: update.states) {
      case .absent:
        return .absent
      case .ambiguous:
        return .unavailable(lastUpdate?.snapshot)
      case .found:
        break
      }
      do {
        return .live(try HomeAssistantEVChargingSnapshot(states: update.states))
      } catch {
        return .unavailable(lastUpdate?.snapshot)
      }
    case .refreshing:
      return .refreshing(
        (try? HomeAssistantEVChargingSnapshot(states: update.states))
          ?? lastUpdate?.snapshot
      )
    case .reconnecting:
      return .reconnecting(reconnectingSnapshot(from: update.states, lastUpdate: lastUpdate))
    case .unavailable:
      return .unavailable(reconnectingSnapshot(from: update.states, lastUpdate: lastUpdate))
    }
  }

  private static func reconnectingSnapshot(
    from states: [HomeAssistantState],
    lastUpdate: HomeAssistantEVChargingUpdate?
  ) -> HomeAssistantEVChargingSnapshot? {
    if let snapshot = try? HomeAssistantEVChargingSnapshot(states: states) {
      return snapshot
    }
    return lastUpdate?.snapshot
  }
}

extension HomeAssistantEVChargingUpdate {
  var snapshot: HomeAssistantEVChargingSnapshot? {
    switch self {
    case .absent:
      nil
    case .live(let snapshot):
      snapshot
    case .refreshing(let snapshot):
      snapshot
    case .reconnecting(let snapshot):
      snapshot
    case .unavailable(let snapshot):
      snapshot
    }
  }
}
