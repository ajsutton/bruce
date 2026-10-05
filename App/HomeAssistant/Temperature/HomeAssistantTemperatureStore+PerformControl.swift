extension HomeAssistantTemperatureStore {
  func performControl(
    for reading: HomeAssistantTemperatureReading,
    intent: ClimateControlIntent,
    allowsAdjustmentReplacement: Bool = false,
    operation: (ClimateControlIntent) async throws -> Void
  ) async {
    guard !Task.isCancelled else { return }
    guard
      let attempt = beginControl(
        for: reading,
        intent: intent,
        allowsAdjustmentReplacement: allowsAdjustmentReplacement
      ),
      attempt.shouldPerform
    else {
      return
    }
    _ = await performQueuedControl(
      for: reading,
      intent: intent,
      sequence: attempt.sequence,
      generation: attempt.generation,
      operation: operation
    )
  }
}
