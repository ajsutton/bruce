extension HomeAssistantTemperatureStore {
  func performControl(
    for reading: HomeAssistantTemperatureReading,
    intent: ClimateControlIntent,
    allowsTargetReplacement: Bool = false,
    operation: (ClimateControlIntent) async throws -> Void
  ) async {
    guard !Task.isCancelled else { return }
    guard
      let attempt = beginControl(
        for: reading,
        intent: intent,
        allowsTargetReplacement: allowsTargetReplacement
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
