import Foundation

actor HomeAssistantStateOrderingCache {
  struct Observation: Sendable {
    let id: UUID
    let snapshot: Snapshot
    let identity: HomeAssistantObservationIdentity
  }

  struct Snapshot: Sendable {
    var states: [HomeAssistantState] = []
    var removals: [String: Date] = [:]
  }

  private var snapshot = Snapshot()
  private var observationID = UUID()
  private var identity: HomeAssistantObservationIdentity?

  func beginObservation(
    for identity: HomeAssistantObservationIdentity
  ) -> Observation {
    if self.identity != identity {
      snapshot = Snapshot()
      self.identity = identity
    }
    observationID = UUID()
    return Observation(id: observationID, snapshot: snapshot, identity: identity)
  }

  func store(_ snapshot: Snapshot, observation: UUID) {
    guard observationID == observation else { return }
    self.snapshot = snapshot
  }
}
