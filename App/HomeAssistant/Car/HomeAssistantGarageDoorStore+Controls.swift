import Foundation

extension HomeAssistantGarageDoorStore {
  func toggleLight(for door: HomeAssistantGarageDoorSnapshot) async {
    guard
      let controller,
      let entityID = door.lightEntityID,
      isLive,
      !isControlling(.light, for: door.id)
    else { return }
    let requestedState: HomeAssistantGarageDoorSnapshot.LightState
    switch door.lightState {
    case .illuminated: requestedState = .off
    case .off: requestedState = .illuminated
    case .unavailable: return
    }
    let operationID = begin(
      .light,
      for: door.id,
      requestedState: .light(requestedState)
    )
    replaceDoor(door.id) { $0.replacing(lightState: requestedState) }
    scheduleControlTimeout(.light, door: door, operationID: operationID)
    do {
      try await controller.setGarageLight(
        entityID: entityID,
        isOn: requestedState == .illuminated
      )
      guard isCurrent(operationID, control: .light, doorID: door.id) else { return }
    } catch {
      guard isCurrent(operationID, control: .light, doorID: door.id) else { return }
      finish(.light, for: door.id, operationID: operationID)
      restoreAuthoritativeDoors()
      guard !Self.isCancellation(error), !Task.isCancelled else { return }
      handleControlFailure(error)
    }
  }

  func toggleLock(for door: HomeAssistantGarageDoorSnapshot) async {
    guard
      let controller,
      let entityID = door.lockEntityID,
      isLive,
      !isControlling(.lock, for: door.id)
    else { return }
    let shouldLock: Bool
    switch door.lockState {
    case .locked, .locking: shouldLock = false
    case .unlocked, .unlocking: shouldLock = true
    case .unavailable: return
    }
    let requestedState: HomeAssistantGarageDoorSnapshot.LockState =
      shouldLock ? .locked : .unlocked
    let operationID = begin(
      .lock,
      for: door.id,
      requestedState: .lock(requestedState)
    )
    replaceDoor(door.id) {
      $0.replacing(lockState: shouldLock ? .locking : .unlocking)
    }
    scheduleControlTimeout(.lock, door: door, operationID: operationID)
    do {
      try await controller.setGarageLock(entityID: entityID, isLocked: shouldLock)
      guard isCurrent(operationID, control: .lock, doorID: door.id) else { return }
    } catch {
      guard isCurrent(operationID, control: .lock, doorID: door.id) else { return }
      finish(.lock, for: door.id, operationID: operationID)
      restoreAuthoritativeDoors()
      guard !Self.isCancellation(error), !Task.isCancelled else { return }
      handleControlFailure(error)
    }
  }

  func send(
    _ command: HomeAssistantGarageDoorCommand,
    to door: HomeAssistantGarageDoorSnapshot
  ) async {
    guard
      let controller,
      isLive,
      pendingDoorCommands[door.id] == nil,
      command != .stop || door.supportsStop
    else { return }
    let operationID = UUID()
    doorOperationIDs[door.id] = operationID
    pendingDoorCommands[door.id] = command
    problem = nil
    scheduleCommandTimeout(command, doorID: door.id, operationID: operationID)
    do {
      try await controller.sendGarageDoorCommand(command, entityID: door.id)
    } catch {
      guard doorOperationIDs[door.id] == operationID else { return }
      finishDoorOperation(doorID: door.id, operationID: operationID)
      guard !Self.isCancellation(error), !Task.isCancelled else { return }
      handleControlFailure(error)
    }
  }

  func isControlling(_ control: Control, for doorID: String) -> Bool {
    controlsInFlight[doorID]?.contains(control) == true
  }

  func reconcileDoorCommands(with doors: [HomeAssistantGarageDoorSnapshot]) {
    for door in doors {
      guard
        let command = pendingDoorCommands[door.id],
        let operationID = doorOperationIDs[door.id],
        command.isConfirmed(by: door.doorState)
      else { continue }
      finishDoorOperation(doorID: door.id, operationID: operationID)
    }
  }

  func reconcileControls(with doors: [HomeAssistantGarageDoorSnapshot]) {
    for door in doors {
      if let operationID = operationID(for: .light, doorID: door.id),
        requestedState(for: .light, doorID: door.id)?.isConfirmed(by: door) == true
      {
        finish(.light, for: door.id, operationID: operationID)
      }
      if let operationID = operationID(for: .lock, doorID: door.id),
        requestedState(for: .lock, doorID: door.id)?.isConfirmed(by: door) == true
      {
        finish(.lock, for: door.id, operationID: operationID)
      }
    }
  }

  func invalidateControls() {
    controlOperationIDs = [:]
    controlRequestedStates = [:]
    doorOperationIDs = [:]
    controlsInFlight = [:]
    pendingDoorCommands = [:]
    controlTimeoutTasks.values.forEach { $0.cancel() }
    controlTimeoutTasks = [:]
    commandTimeoutTasks.values.forEach { $0.cancel() }
    commandTimeoutTasks = [:]
    restoreAuthoritativeDoors()
  }
}

extension HomeAssistantGarageDoorStore {
  enum Control: Hashable {
    case light
    case lock
  }

  struct ControlOperationKey: Hashable {
    let doorID: String
    let control: Control
  }

  enum ControlRequestedState: Equatable {
    case light(HomeAssistantGarageDoorSnapshot.LightState)
    case lock(HomeAssistantGarageDoorSnapshot.LockState)

    func isConfirmed(by door: HomeAssistantGarageDoorSnapshot) -> Bool {
      switch self {
      case .light(let state): door.lightState == state
      case .lock(let state): door.lockState == state
      }
    }
  }

  private func begin(
    _ control: Control,
    for doorID: String,
    requestedState: ControlRequestedState
  ) -> UUID {
    let operationID = UUID()
    let key = ControlOperationKey(doorID: doorID, control: control)
    controlOperationIDs[key] = operationID
    controlRequestedStates[key] = requestedState
    controlsInFlight[doorID, default: []].insert(control)
    problem = nil
    return operationID
  }

  private func finish(_ control: Control, for doorID: String, operationID: UUID) {
    let key = ControlOperationKey(doorID: doorID, control: control)
    guard controlOperationIDs[key] == operationID else { return }
    controlOperationIDs[key] = nil
    controlRequestedStates[key] = nil
    controlTimeoutTasks[key]?.cancel()
    controlTimeoutTasks[key] = nil
    controlsInFlight[doorID]?.remove(control)
    if controlsInFlight[doorID]?.isEmpty == true {
      controlsInFlight[doorID] = nil
    }
  }

  private func operationID(for control: Control, doorID: String) -> UUID? {
    controlOperationIDs[ControlOperationKey(doorID: doorID, control: control)]
  }

  private func requestedState(
    for control: Control,
    doorID: String
  ) -> ControlRequestedState? {
    controlRequestedStates[ControlOperationKey(doorID: doorID, control: control)]
  }

  private func isCurrent(_ operationID: UUID, control: Control, doorID: String) -> Bool {
    self.operationID(for: control, doorID: doorID) == operationID
  }

  private func finishDoorOperation(doorID: String, operationID: UUID) {
    guard doorOperationIDs[doorID] == operationID else { return }
    doorOperationIDs[doorID] = nil
    pendingDoorCommands[doorID] = nil
    commandTimeoutTasks[doorID]?.cancel()
    commandTimeoutTasks[doorID] = nil
  }

  private func replaceDoor(
    _ doorID: String,
    transform: (HomeAssistantGarageDoorSnapshot) -> HomeAssistantGarageDoorSnapshot
  ) {
    guard let index = doors.firstIndex(where: { $0.id == doorID }) else { return }
    doors[index] = transform(doors[index])
  }

  func restoreAuthoritativeDoors() {
    doors = authoritativeDoors.map(applyingPendingControl)
  }

  func applyingPendingControl(
    to door: HomeAssistantGarageDoorSnapshot
  ) -> HomeAssistantGarageDoorSnapshot {
    var presented = door
    let lightKey = ControlOperationKey(doorID: door.id, control: .light)
    if case .light(let state) = controlRequestedStates[lightKey] {
      presented = presented.replacing(lightState: state)
    }
    let lockKey = ControlOperationKey(doorID: door.id, control: .lock)
    if case .lock(let state) = controlRequestedStates[lockKey] {
      presented = presented.replacing(
        lockState: state == .locked ? .locking : .unlocking
      )
    }
    return presented
  }

  private func handleControlFailure(_ error: any Error) {
    let mappedProblem = Self.problem(for: error)
    problem =
      mappedProblem == .signInRequired || mappedProblem == .connectionUnavailable
      ? mappedProblem
      : .updateFailed
    if mappedProblem == .signInRequired {
      onAuthenticationRequired()
    }
  }
}

extension HomeAssistantGarageDoorCommand {
  fileprivate func isConfirmed(
    by state: HomeAssistantGarageDoorSnapshot.DoorState
  ) -> Bool {
    switch self {
    case .open: state == .opening || state == .open
    case .close: state == .closing || state == .closed
    case .stop: state == .open || state == .partlyOpen || state == .closed
    }
  }
}
