import SwiftUI

struct HomeAssistantClimateZoneCard: View, Equatable {
  private let temperatureCard: HomeAssistantTemperatureCard

  init(
    reading: HomeAssistantTemperatureReading,
    mode: BruceMode,
    store: HomeAssistantTemperatureStore,
    isLastKnown: Bool,
    targetValueFractionLength: Int
  ) {
    let setPower: (Bool) -> Void = { isOn in
      Task { await store.setPower(for: reading, isOn: isOn) }
    }
    temperatureCard = HomeAssistantTemperatureCard(
      reading: reading, mode: mode,
      showsControl: reading.kind == .zone && store.supportsControl,
      isControlEnabled: store.canControl(reading),
      isControlling: store.isControllingClimateState(entityID: reading.id),
      isAdjustmentControlling: store.isAdjusting(entityID: reading.id),
      isLastKnown: isLastKnown,
      showsAdjustmentControl: reading.kind == .zone && reading.adjustmentValue != nil
        && store.supportsControl,
      adjustmentFractionLength: reading.isSensorlessZone ? 0 : targetValueFractionLength,
      setPower: setPower,
      setAdjustmentValue: { value in
        MainActor.assumeIsolated {
          if reading.isSensorlessZone {
            store.setOpening(value, for: reading)
          } else {
            store.setTargetValue(value, for: reading)
          }
        }
      }
    )
  }

  var body: some View {
    temperatureCard
  }

  nonisolated static func == (lhs: Self, rhs: Self) -> Bool {
    lhs.temperatureCard == rhs.temperatureCard
  }
}
