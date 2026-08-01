import Foundation

extension HomeAssistantTemperatureStore {
  func apply(_ preset: HomeAssistantClimatePreset) {
    guard presetControlTask == nil else { return }
    let generation = UUID()
    presetControlGeneration = generation
    presetControlTask = Task { [weak self] in
      guard let self else { return }
      await performPreset(preset, generation: generation)
      guard presetControlGeneration == generation else { return }
      presetControlTask = nil
      completePresetTransactionIfConfirmed(generation: generation)
    }
  }

  private func performPreset(
    _ preset: HomeAssistantClimatePreset,
    generation: UUID
  ) async {
    guard let controller else { return }
    let currentPresets = HomeAssistantTemperatureSummary(readings: readings).climatePresets
    guard
      let currentPreset = currentPresets.first(where: { $0.id == preset.id }),
      currentPreset.zoneEntityIDs == preset.zoneEntityIDs
    else { return }
    let zones = readings.filter { $0.kind == .zone }
    let zoneEntityIDs = Set(zones.map(\.id))
    guard
      currentPreset.zoneEntityIDs.isSubset(of: zoneEntityIDs),
      zones.allSatisfy(canControlDuringPreset),
      zones.allSatisfy({ !isControlling(entityID: $0.id) })
    else { return }

    let zonesToTurnOff = zones.filter {
      !currentPreset.zoneEntityIDs.contains($0.id) && $0.powerState == .poweredOn
    }
    let zonesToTurnOn = zones.filter {
      currentPreset.zoneEntityIDs.contains($0.id) && $0.powerState == .off
    }
    let controls = (zonesToTurnOff + zonesToTurnOn).compactMap { zone in
      let isOn = currentPreset.zoneEntityIDs.contains(zone.id)
      return beginControl(
        for: zone,
        intent: .power(isOn: isOn),
        allowsTargetReplacement: false,
        allowsPresetTransaction: true,
        publishesReadings: false
      ).map {
        PresetClimateControl(reading: zone, isOn: isOn, attempt: $0)
      }
    }
    guard controls.count == zonesToTurnOff.count + zonesToTurnOn.count else {
      rollback(controls)
      return
    }
    guard !controls.isEmpty else { return }
    presetTransaction = PresetClimateTransaction(
      generation: generation,
      presetID: currentPreset.id,
      allZoneEntityIDs: zoneEntityIDs,
      memberEntityIDs: currentPreset.zoneEntityIDs,
      controlledEntityIDs: Set(controls.map { $0.reading.id }),
      reportSequence: controls.map(\.attempt.sequence).max() ?? 0
    )
    publishReadings()
    await perform(controls, generation: generation, with: controller)
  }

  private func perform(
    _ controls: [PresetClimateControl],
    generation: UUID,
    with controller: any HomeAssistantClimateControlling
  ) async {
    for control in controls {
      guard
        !Task.isCancelled,
        validatePresetTransaction(generation: generation)
      else { return }
      let succeeded = await performQueuedControl(
        for: control.reading,
        intent: .power(isOn: control.isOn),
        sequence: control.attempt.sequence,
        generation: control.attempt.generation
      ) { _ in
        try await controller.setPower(
          entityID: control.reading.id,
          isOn: control.isOn
        )
      }
      guard succeeded else {
        failPresetTransaction(generation: generation)
        return
      }
    }
  }

  private func rollback(
    _ controls: [PresetClimateControl]
  ) {
    for control in controls {
      rejectControl(
        for: control.reading.id,
        generation: control.attempt.generation,
        publishesReadings: false
      )
    }
    publishReadings()
  }
}

private struct PresetClimateControl {
  let reading: HomeAssistantTemperatureReading
  let isOn: Bool
  let attempt: ClimateControlAttempt
}
