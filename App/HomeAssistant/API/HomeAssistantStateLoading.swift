import Foundation

struct HomeAssistantStateUpdate: Sendable, Equatable {
  enum Phase: Sendable, Equatable {
    case live
    case refreshing
    case reconnecting
  }

  let phase: Phase
  let states: [HomeAssistantState]
  let generation: UUID

  static func live(
    _ states: [HomeAssistantState],
    generation: UUID = UUID()
  ) -> Self {
    Self(
      phase: .live,
      states: states,
      generation: generation
    )
  }

  static func refreshing(
    _ states: [HomeAssistantState],
    generation: UUID = UUID()
  ) -> Self {
    Self(
      phase: .refreshing,
      states: states,
      generation: generation
    )
  }

  static func reconnecting(
    _ states: [HomeAssistantState],
    generation: UUID = UUID()
  ) -> Self {
    Self(
      phase: .reconnecting,
      states: states,
      generation: generation
    )
  }

  func preservingControlTransition(from dropped: Self) -> Self? {
    guard phase == .live, dropped.phase != .live else { return nil }
    return Self(
      phase: dropped.phase,
      states: states,
      generation: generation
    )
  }

  func preservingLiveTransition(from dropped: Self) -> Self? {
    guard phase == .live, dropped.phase == .live else { return nil }
    guard states.count == dropped.states.count else { return dropped }
    let statePairs = zip(states, dropped.states)
    let hasAvailabilityTransition = statePairs.contains { latest, previous in
      latest.entityID != previous.entityID
        || latest.isAvailable != previous.isAvailable
    }
    return hasAvailabilityTransition ? dropped : nil
  }
}

extension HomeAssistantStateUpdate: HomeAssistantBufferedUpdate {
  var isLiveUpdate: Bool { phase == .live }
}

protocol HomeAssistantStateLoading: Sendable {
  func stateUpdates() async -> HomeAssistantBufferedUpdateStream<
    HomeAssistantStateUpdate
  >
  func refresh() async -> Bool
}

extension HomeAssistantStateLoading {
  func refresh() async -> Bool { false }
}
