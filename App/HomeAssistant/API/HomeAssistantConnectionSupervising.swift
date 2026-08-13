import Foundation

protocol HomeAssistantConnectionSupervising: Sendable {
  func requireFreshLiveData() async throws
  func prepareForDisconnect() async -> UUID
  func recoverFromFailedDisconnect(preparationID: UUID) async
  func stop() async
}

extension HomeAssistantConnectionSupervisor: HomeAssistantConnectionSupervising {}

extension HomeAssistantConnectionSupervisor {
  func refresh() async -> Bool {
    guard !continuations.isEmpty else { return false }
    requestReplacement(trigger: .manualRequest)
    return true
  }

  func receivePathHint() {
    guard
      !acceleratedReplacementPending,
      state == .backingOff || state == .waitingForConnectivity
    else { return }
    acceleratedReplacementPending = true
    requestReplacement(trigger: .pathHint)
  }

  func receiveWakeHint() {
    guard
      !acceleratedReplacementPending,
      state == .live || state == .backingOff || state == .waitingForConnectivity
    else { return }
    acceleratedReplacementPending = true
    requestReplacement(trigger: .wakeHint)
  }
}
