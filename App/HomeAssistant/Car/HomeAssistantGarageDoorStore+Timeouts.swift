import Foundation

extension HomeAssistantGarageDoorStore {
  func scheduleCommandTimeout(
    _ command: HomeAssistantGarageDoorCommand,
    doorID: String,
    operationID: UUID
  ) {
    commandTimeoutTasks[doorID]?.cancel()
    commandTimeoutTasks[doorID] = Task { [weak self, commandTimeout, timeoutSleep] in
      await timeoutSleep(commandTimeout)
      guard
        !Task.isCancelled,
        self?.doorOperationIDs[doorID] == operationID,
        self?.pendingDoorCommands[doorID] == command
      else { return }
      self?.pendingDoorCommands[doorID] = nil
      self?.doorOperationIDs[doorID] = nil
      self?.problem = .updateFailed
      self?.commandTimeoutTasks[doorID] = nil
    }
  }

  func scheduleControlTimeout(
    _ control: Control,
    door: HomeAssistantGarageDoorSnapshot,
    operationID: UUID
  ) {
    let key = ControlOperationKey(doorID: door.id, control: control)
    controlTimeoutTasks[key]?.cancel()
    controlTimeoutTasks[key] = Task { [weak self, commandTimeout, timeoutSleep] in
      await timeoutSleep(commandTimeout)
      guard
        !Task.isCancelled,
        self?.controlOperationIDs[key] == operationID
      else { return }
      self?.timeOutControl(
        control,
        door: door,
        operationID: operationID
      )
    }
  }

  private func timeOutControl(
    _ control: Control,
    door: HomeAssistantGarageDoorSnapshot,
    operationID: UUID
  ) {
    guard
      controlOperationIDs[ControlOperationKey(doorID: door.id, control: control)]
        == operationID
    else { return }
    let key = ControlOperationKey(doorID: door.id, control: control)
    controlOperationIDs[key] = nil
    controlRequestedStates[key] = nil
    controlsInFlight[door.id]?.remove(control)
    if controlsInFlight[door.id]?.isEmpty == true {
      controlsInFlight[door.id] = nil
    }
    controlTimeoutTasks[key] = nil
    restoreAuthoritativeDoors()
    problem = .updateFailed
  }
}
