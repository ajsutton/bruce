import SwiftUI

struct HomeAssistantClimateZoneCard: View, Equatable {
  private let temperatureCard: HomeAssistantTemperatureCard
  private let openingCard: SensorlessZoneCard

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
      isTargetControlling: store.isAdjusting(entityID: reading.id),
      isLastKnown: isLastKnown,
      showsTargetControl: reading.kind == .zone && reading.targetValue != nil
        && store.supportsControl,
      targetValueFractionLength: targetValueFractionLength,
      setPower: setPower,
      setTargetValue: { value in
        MainActor.assumeIsolated { store.setTargetValue(value, for: reading) }
      }
    )
    openingCard = SensorlessZoneCard(
      reading: reading, mode: mode, showsControls: store.supportsControl,
      isEnabled: store.canControl(reading),
      isAdjustingOpening: store.isAdjusting(entityID: reading.id),
      isControllingPower: store.isControllingClimateState(entityID: reading.id),
      isLastKnown: isLastKnown, setPower: setPower,
      setOpening: { value in
        MainActor.assumeIsolated { store.setOpening(value, for: reading) }
      }
    )
  }

  var body: some View {
    if temperatureCard.reading.kind == .zone && temperatureCard.reading.value == nil
      && temperatureCard.reading.targetValue == nil
    {
      openingCard
    } else {
      temperatureCard
    }
  }

  nonisolated static func == (lhs: Self, rhs: Self) -> Bool {
    lhs.temperatureCard == rhs.temperatureCard
  }
}
