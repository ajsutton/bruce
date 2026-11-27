extension HomeAssistantTemperatureStore {
  func setPower(
    for reading: HomeAssistantTemperatureReading,
    isOn: Bool
  ) async {
    guard let controller,
      let current = serverReadings.first(where: { $0.id == reading.id })
    else { return }
    if isOn, current.kind == .airConditioner, let mode = selectedClimateMode(for: current) {
      await performControl(for: current, intent: .mode(mode)) { _ in
        try await controller.setMode(mode, entityID: current.id)
      }
    } else {
      await performControl(for: current, intent: .power(isOn: isOn)) { _ in
        try await controller.setPower(entityID: current.id, isOn: isOn)
      }
    }
  }
  func setMode(
    _ mode: HomeAssistantTemperatureReading.ClimateMode,
    for reading: HomeAssistantTemperatureReading
  ) async {
    guard !Task.isCancelled, let controller,
      let current = serverReadings.first(where: { $0.id == reading.id }),
      current.availableModes.contains(mode), canControl(current),
      !isControlling(entityID: current.id)
    else { return }
    if selectClimateModeIfOff(mode, for: current) { return }
    await performControl(for: current, intent: .mode(mode)) { _ in
      try await controller.setMode(mode, entityID: current.id)
    }
  }

  /// Commit an off-state selection before a subsequent power tap can start a command.
  func selectClimateModeIfOff(
    _ mode: HomeAssistantTemperatureReading.ClimateMode,
    for reading: HomeAssistantTemperatureReading
  ) -> Bool {
    guard let current = serverReadings.first(where: { $0.id == reading.id }),
      current.kind == .airConditioner, current.powerState == .off,
      current.availableModes.contains(mode), canControl(current),
      !isControlling(entityID: current.id)
    else { return false }
    rememberClimateMode(mode, entityID: current.id)
    return true
  }

  func selectedClimateMode(
    for reading: HomeAssistantTemperatureReading
  ) -> HomeAssistantTemperatureReading.ClimateMode? {
    reading.preferredClimateMode(remembered: rememberedClimateModes[reading.id])
  }

  func rememberClimateMode(
    _ mode: HomeAssistantTemperatureReading.ClimateMode,
    entityID: String
  ) {
    var modes = rememberedClimateModes
    modes[entityID] = mode
    updateRememberedClimateModes(modes)
  }

  func rememberConfirmedClimateModes(_ readings: [HomeAssistantTemperatureReading]) {
    var modes = rememberedClimateModes
    for reading in readings
    where reading.kind == .airConditioner && reading.powerState == .poweredOn {
      if let mode = reading.operatingMode.climateMode, reading.availableModes.contains(mode) {
        modes[reading.id] = mode
      }
    }
    updateRememberedClimateModes(modes)
  }
}
