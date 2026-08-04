enum HomeAssistantEVChargingUpdate: Equatable, Sendable {
  case absent
  case live(HomeAssistantEVChargingSnapshot)
  case refreshing(HomeAssistantEVChargingSnapshot?)
  case reconnecting(HomeAssistantEVChargingSnapshot?)
  case unavailable(HomeAssistantEVChargingSnapshot?)
}

typealias HomeAssistantEVChargingUpdateStream = HomeAssistantBufferedUpdateStream<
  HomeAssistantEVChargingUpdate
>

protocol HomeAssistantEVCharging: Sendable {
  var providesContinuousUpdates: Bool { get }

  func evChargingUpdates() -> HomeAssistantEVChargingUpdateStream
  func loadEVChargingMode() async throws -> HomeAssistantEVChargingMode
  func loadEVChargingSnapshot() async throws -> HomeAssistantEVChargingSnapshot
  func setEVChargingMode(
    _ mode: HomeAssistantEVChargingMode
  ) async throws -> HomeAssistantEVChargingMode
}

extension HomeAssistantEVCharging {
  var providesContinuousUpdates: Bool { false }

  func evChargingUpdates() -> HomeAssistantEVChargingUpdateStream {
    HomeAssistantEVChargingUpdateStream { continuation in
      let task = Task {
        do {
          continuation.yield(.live(try await loadEVChargingSnapshot()))
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

  func loadEVChargingSnapshot() async throws -> HomeAssistantEVChargingSnapshot {
    HomeAssistantEVChargingSnapshot(
      mode: try await loadEVChargingMode(),
      activity: .unavailable
    )
  }
}

extension HomeAssistantEVChargingUpdate: HomeAssistantBufferedUpdate {
  var isLiveUpdate: Bool {
    switch self {
    case .absent, .live: true
    case .refreshing, .reconnecting, .unavailable: false
    }
  }

  func preservingControlTransition(from dropped: Self) -> Self? {
    guard isLiveUpdate else { return nil }
    return switch dropped {
    case .refreshing:
      .refreshing(snapshot)
    case .reconnecting:
      .reconnecting(snapshot)
    case .unavailable:
      .unavailable(snapshot)
    case .absent, .live:
      nil
    }
  }

  func preservingLiveTransition(from dropped: Self) -> Self? {
    guard isLiveUpdate, dropped.isLiveUpdate else { return nil }
    guard availabilitySignature != dropped.availabilitySignature else { return nil }
    return dropped
  }

  private var availabilitySignature: EVChargingAvailabilitySignature {
    EVChargingAvailabilitySignature(update: self)
  }
}

private struct EVChargingAvailabilitySignature: Equatable {
  let hasMode: Bool
  let hasActivity: Bool
  let decisionFields: [Bool]

  init(update: HomeAssistantEVChargingUpdate) {
    let snapshot = update.snapshot
    hasMode = snapshot != nil
    hasActivity = snapshot?.activity != .unavailable
    decisionFields = [
      snapshot?.decision.isChargingDesired != nil,
      snapshot?.decision.overnightSafeChargingMinutes != nil,
      snapshot?.decision.priceAllowsCharging != nil,
      snapshot?.decision.currentPriceDollarsPerKilowattHour != nil,
      snapshot?.decision.batteryStateOfCharge != nil,
    ]
  }
}
