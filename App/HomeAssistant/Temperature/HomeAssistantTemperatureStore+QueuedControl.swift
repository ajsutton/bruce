import Foundation

extension HomeAssistantTemperatureStore {
  func beginControl(
    for reading: HomeAssistantTemperatureReading,
    intent: ClimateControlIntent,
    allowsTargetReplacement: Bool,
    allowsPresetTransaction: Bool = false,
    publishesReadings: Bool = true
  ) -> ClimateControlAttempt? {
    guard
      allowsPresetTransaction ? canControlDuringPreset(reading) : canControl(reading)
    else { return nil }
    let currentControl = pendingControls[reading.id]
    guard
      currentControl == nil
        || (allowsTargetReplacement && currentControl?.intent.isTargetValue == true)
    else { return nil }
    latestControlSequence += 1
    let sequence = latestControlSequence
    controllingEntityIDs.insert(reading.id)
    pendingControls[reading.id] = PendingClimateControl(
      intent: intent,
      sequence: sequence,
      isAccepted: false
    )
    if publishesReadings { publishReadings() }
    controlProblem = nil
    presentedControlProblemSequence = nil
    confirmationTasks.removeValue(forKey: reading.id)?.cancel()
    return ClimateControlAttempt(
      generation: controlGeneration,
      sequence: sequence,
      shouldPerform: currentControl?.isAccepted != false
    )
  }

  func performQueuedControl(
    for reading: HomeAssistantTemperatureReading,
    intent: ClimateControlIntent,
    sequence: Int,
    generation: UUID,
    operation: (ClimateControlIntent) async throws -> Void
  ) async -> Bool {
    var activeIntent = intent
    var activeSequence = sequence
    while true {
      guard controlGeneration == generation else { return false }
      let result: Result<Void, any Error>
      do {
        try await operation(activeIntent)
        result = .success(())
      } catch {
        result = .failure(error)
      }
      guard controlGeneration == generation else { return false }
      if let replacement = pendingControls[reading.id],
        replacement.sequence != activeSequence
      {
        activeIntent = replacement.intent
        activeSequence = replacement.sequence
        continue
      }
      switch result {
      case .success:
        pendingControls[reading.id]?.isAccepted = true
        finishConfirmedControls()
        if pendingControls[reading.id]?.isAccepted == true {
          scheduleConfirmationTimeout(
            for: reading,
            generation: generation,
            sequence: activeSequence
          )
        }
        return true
      case .failure(let error):
        rejectControl(for: reading.id, generation: generation)
        guard !Self.isCancellation(error), !Task.isCancelled else { return false }
        if Self.problem(for: error) == .signInRequired { onAuthenticationRequired() }
        reportControlProblem(for: reading.name, sequence: activeSequence)
        return false
      }
    }
  }
}
