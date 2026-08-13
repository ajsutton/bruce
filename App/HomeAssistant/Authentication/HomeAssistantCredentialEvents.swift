import Foundation

struct HomeAssistantCredentialSnapshot: Equatable, Sendable {
  let authenticationSessionEpoch: Int
  let persistenceGeneration: Int
  let availability: Availability

  enum Availability: Equatable, Sendable {
    case ready
    case missing
    case rejected
  }
}

actor HomeAssistantCredentialEvents {
  private var continuations: [UUID: AsyncStream<HomeAssistantCredentialSnapshot>.Continuation] = [:]
  private var latest: HomeAssistantCredentialSnapshot?

  func updates() -> AsyncStream<HomeAssistantCredentialSnapshot> {
    AsyncStream { continuation in
      let id = UUID()
      continuations[id] = continuation
      if let latest {
        continuation.yield(latest)
      }
      continuation.onTermination = { _ in
        Task { await self.remove(id) }
      }
    }
  }

  func publish(_ snapshot: HomeAssistantCredentialSnapshot) {
    latest = snapshot
    continuations.values.forEach { $0.yield(snapshot) }
  }

  private func remove(_ id: UUID) {
    continuations[id] = nil
  }
}
