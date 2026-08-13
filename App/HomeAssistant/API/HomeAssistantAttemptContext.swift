import Foundation

struct HomeAssistantAttemptContext {
  let id: UUID
  let startedAt: TimeInterval
  let access: HomeAssistantWebSocketAccess
  let connection: any HomeAssistantWebSocketConnection
  let attempt: HomeAssistantConnectionAttempt
}

struct HomeAssistantSynchronizedAttempt {
  let subscriptions: [Int: String]
  let events: HomeAssistantConnectionEventSequence
  var snapshot: HomeAssistantStateReconciler.Snapshot
  var generation: UUID
}

extension HomeAssistantConnectionSupervisor {
  static let logicalEventTypes = [
    "state_changed",
    "entity_registry_updated",
    "device_registry_updated",
    "area_registry_updated",
    "floor_registry_updated",
    "label_registry_updated",
  ]
}
