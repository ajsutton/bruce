import Foundation

struct HomeAssistantZoneOpening: Equatable, Sendable {
  let entityID: String
  let value: Double?
  let isAvailable: Bool
  let supportsPosition: Bool

  init(entityID: String, value: Double?, isAvailable: Bool, supportsPosition: Bool) {
    self.entityID = entityID
    self.value = value
    self.isAvailable = isAvailable
    self.supportsPosition = supportsPosition
  }

  init(state: HomeAssistantState) {
    entityID = state.entityID
    value = state.currentPosition.flatMap { $0.isFinite && (0...100).contains($0) ? $0 : nil }
    isAvailable = state.isAvailable
    supportsPosition = state.supportedFeatures & 4 != 0
  }

  func canSetValue(_ value: Double) -> Bool {
    isAvailable && supportsPosition && self.value != nil
      && value.isFinite && (0...100).contains(value) && value.rounded() == value
  }

  func replacingValue(_ value: Double) -> Self {
    Self(
      entityID: entityID, value: value, isAvailable: isAvailable, supportsPosition: supportsPosition
    )
  }
}
