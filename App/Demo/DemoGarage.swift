import Foundation

final class DemoGarage: HomeAssistantGarageDoorLoading, HomeAssistantGarageDoorControlling {
  private let state = DemoValue(
    HomeAssistantGarageDoorSnapshot(
      id: "cover.garage", name: "Garage", doorState: .closed,
      lightState: .off, lockState: .unlocked,
      lightEntityID: "light.garage", lockEntityID: "lock.garage"
    )
  )

  var providesContinuousUpdates: Bool { true }

  func loadGarageDoors() async throws -> [HomeAssistantGarageDoorSnapshot] { [state.value] }

  func garageDoorUpdates() -> HomeAssistantGarageDoorUpdateStream {
    HomeAssistantGarageDoorUpdateStream { [state] continuation in
      let id = state.observe { continuation.yield(.live([$0])) }
      continuation.onTermination = { [weak state] _ in state?.removeObserver(id) }
    }
  }

  func setGarageLight(entityID: String, isOn: Bool) async throws {
    try Task.checkCancellation()
    guard entityID == state.value.lightEntityID else { throw DemoHomeError.unknownEntity }
    state.update { $0 = $0.replacing(lightState: isOn ? .illuminated : .off) }
  }

  func setGarageLock(entityID: String, isLocked: Bool) async throws {
    try Task.checkCancellation()
    guard entityID == state.value.lockEntityID else { throw DemoHomeError.unknownEntity }
    state.update { $0 = $0.replacing(lockState: isLocked ? .locked : .unlocked) }
  }

  func sendGarageDoorCommand(
    _ command: HomeAssistantGarageDoorCommand, entityID: String
  ) async throws {
    try Task.checkCancellation()
    guard entityID == state.value.id else { throw DemoHomeError.unknownEntity }
    state.update { door in
      let doorState: HomeAssistantGarageDoorSnapshot.DoorState
      switch command {
      case .open: doorState = .open
      case .close: doorState = .closed
      case .stop: doorState = .partlyOpen
      }
      door = HomeAssistantGarageDoorSnapshot(
        id: door.id, name: door.name, doorState: doorState,
        lightState: door.lightState, lockState: door.lockState,
        lightEntityID: door.lightEntityID, lockEntityID: door.lockEntityID,
        supportsStop: door.supportsStop
      )
    }
  }
}
