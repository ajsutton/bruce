import Foundation

extension HomeAssistantTemperatureStore {
  func failPresetTransactionIfInvalid() {
    guard let transaction = presetTransaction else { return }
    _ = validatePresetTransaction(
      generation: transaction.generation,
      reportsProblem: true
    )
  }

  func completePresetTransactionIfConfirmed(generation: UUID? = nil) {
    guard
      let transaction = presetTransaction,
      generation.map({ $0 == transaction.generation }) ?? true,
      transaction.controlledEntityIDs.allSatisfy({ pendingControls[$0] == nil })
    else { return }
    presetTransaction = nil
  }

  func failPresetTransactionIfNeeded(for entityID: String) -> Bool {
    guard
      let transaction = presetTransaction,
      transaction.controlledEntityIDs.contains(entityID)
    else { return false }
    failPresetTransaction(generation: transaction.generation)
    return true
  }

  func validatePresetTransaction(
    generation: UUID,
    reportsProblem: Bool = false
  ) -> Bool {
    guard
      let transaction = presetTransaction,
      transaction.generation == generation
    else { return false }
    let zones = serverReadings.filter { $0.kind == .zone }
    let currentPreset = HomeAssistantTemperatureSummary(readings: serverReadings)
      .climatePresets.first { $0.id == transaction.presetID }
    let invalidZone = zones.first { zone in
      zone.powerState == .unavailable
        || (!transaction.controlledEntityIDs.contains(zone.id)
          && zone.powerState != transaction.expectedPowerState(for: zone.id))
        || (pendingControls[zone.id] == nil
          && zone.powerState != transaction.expectedPowerState(for: zone.id))
    }
    guard
      Set(zones.map(\.id)) == transaction.allZoneEntityIDs,
      currentPreset?.zoneEntityIDs == transaction.memberEntityIDs,
      invalidZone == nil
    else {
      let name = invalidZone?.name ?? currentPreset?.name ?? "Climate"
      failPresetTransaction(generation: generation)
      if reportsProblem {
        reportControlProblem(for: name, sequence: transaction.reportSequence)
      }
      return false
    }
    return true
  }

  func failPresetTransaction(generation: UUID) {
    guard
      let transaction = presetTransaction,
      transaction.generation == generation
    else { return }
    let task = presetControlTask
    presetControlGeneration = UUID()
    presetControlTask = nil
    presetTransaction = nil
    for entityID in transaction.controlledEntityIDs {
      rejectControl(
        for: entityID,
        generation: controlGeneration,
        publishesReadings: false
      )
    }
    controlGeneration = UUID()
    task?.cancel()
    publishReadings()
  }
}

struct PresetClimateTransaction {
  let generation: UUID
  let presetID: HomeAssistantClimatePreset.Identifier
  let allZoneEntityIDs: Set<String>
  let memberEntityIDs: Set<String>
  let controlledEntityIDs: Set<String>
  let reportSequence: Int

  func expectedPowerState(
    for entityID: String
  ) -> HomeAssistantTemperatureReading.PowerState {
    memberEntityIDs.contains(entityID) ? .poweredOn : .off
  }
}
