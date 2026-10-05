import Foundation

extension HomeAssistantTemperatureStore {
  func setTargetValue(_ value: Double, for reading: HomeAssistantTemperatureReading) {
    guard let controller,
      let current = serverReadings.first(where: { $0.id == reading.id }),
      current.canSetTargetValue(value)
    else { return }
    queueAdjustment(.targetValue(value), for: current) { intent in
      guard case .targetValue(let latestValue) = intent else {
        throw HomeAssistantAPIError.invalidResponse
      }
      try await controller.setTargetValue(latestValue, entityID: current.id)
    }
  }

  func setOpening(_ value: Double, for reading: HomeAssistantTemperatureReading) {
    guard let controller,
      let current = serverReadings.first(where: { $0.id == reading.id }),
      current.value == nil, current.targetValue == nil,
      let opening = current.opening, opening.canSetValue(value)
    else { return }
    queueAdjustment(.opening(value: value, entityID: opening.entityID), for: current) { intent in
      guard case .opening(let latestValue, let entityID) = intent else {
        throw HomeAssistantAPIError.invalidResponse
      }
      try await controller.setOpening(latestValue, entityID: entityID)
    }
  }
}

extension HomeAssistantTemperatureStore {
  fileprivate func queueAdjustment(
    _ intent: ClimateControlIntent,
    for reading: HomeAssistantTemperatureReading,
    operation: @escaping @MainActor (ClimateControlIntent) async throws -> Void
  ) {
    guard
      let attempt = beginControl(
        for: reading, intent: intent, allowsAdjustmentReplacement: true
      ), attempt.shouldPerform
    else { return }
    adjustmentControlTasks[reading.id] = Task { [weak self] in
      guard let self else { return }
      _ = await performQueuedControl(
        for: reading, intent: intent, sequence: attempt.sequence, generation: attempt.generation,
        operation: operation
      )
      if controlGeneration == attempt.generation {
        adjustmentControlTasks[reading.id] = nil
      }
    }
  }
}
