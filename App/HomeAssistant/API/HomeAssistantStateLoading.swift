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
    Self(phase: .live, states: states, generation: generation)
  }

  static func refreshing(
    _ states: [HomeAssistantState],
    generation: UUID = UUID()
  ) -> Self {
    Self(phase: .refreshing, states: states, generation: generation)
  }

  static func reconnecting(
    _ states: [HomeAssistantState],
    generation: UUID = UUID()
  ) -> Self {
    Self(phase: .reconnecting, states: states, generation: generation)
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
