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
  let requiresHistoryBackfill: Bool

  static func live(
    _ states: [HomeAssistantState],
    generation: UUID = UUID(),
    requiresHistoryBackfill: Bool = false
  ) -> Self {
    Self(
      phase: .live,
      states: states,
      generation: generation,
      requiresHistoryBackfill: requiresHistoryBackfill
    )
  }

  static func refreshing(
    _ states: [HomeAssistantState],
    generation: UUID = UUID(),
    requiresHistoryBackfill: Bool = false
  ) -> Self {
    Self(
      phase: .refreshing,
      states: states,
      generation: generation,
      requiresHistoryBackfill: requiresHistoryBackfill
    )
  }

  static func reconnecting(
    _ states: [HomeAssistantState],
    generation: UUID = UUID(),
    requiresHistoryBackfill: Bool = false
  ) -> Self {
    Self(
      phase: .reconnecting,
      states: states,
      generation: generation,
      requiresHistoryBackfill: requiresHistoryBackfill
    )
  }

  func requiringHistoryBackfill() -> Self {
    Self(
      phase: phase,
      states: states,
      generation: generation,
      requiresHistoryBackfill: true
    )
  }
}

protocol HomeAssistantStateLoading: Sendable {
  func stateUpdates() async -> AsyncThrowingStream<
    HomeAssistantStateUpdate, any Error
  >
  func refresh() async -> Bool
}

extension HomeAssistantStateLoading {
  func refresh() async -> Bool { false }
}
