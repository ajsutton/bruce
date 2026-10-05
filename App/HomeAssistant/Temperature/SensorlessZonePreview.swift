import SwiftUI

#Preview("Kitchen") {
  SensorlessZoneCard(
    reading: sensorlessKitchen, mode: .standard, showsControls: true, isEnabled: true,
    isAdjustingOpening: false, isControllingPower: false, isLastKnown: false,
    setPower: { _ in }, setOpening: { _ in }
  )
  .frame(width: 320)
  .padding()
}

#Preview("Kitchen · Full Bruce · large text") {
  SensorlessZoneCard(
    reading: sensorlessKitchen, mode: .full, showsControls: true, isEnabled: true,
    isAdjustingOpening: false, isControllingPower: false, isLastKnown: false,
    setPower: { _ in }, setOpening: { _ in }
  )
  .environment(\.dynamicTypeSize, .accessibility3)
  .frame(width: 320)
  .padding()
}

private let sensorlessKitchen = HomeAssistantTemperatureReading(
  id: "climate.kitchen", name: "Kitchen", value: nil, targetValue: nil,
  unit: "°C", powerState: .off, kind: .zone, operatingMode: .off,
  opening: HomeAssistantZoneOpening(
    entityID: "cover.kitchen_damper", value: 5, isAvailable: true, supportsPosition: true
  )
)
