import SwiftUI

#Preview("Kitchen") {
  HomeAssistantTemperatureCard(
    reading: sensorlessKitchen, mode: .standard, showsControl: true, isControlEnabled: true,
    showsAdjustmentControl: true
  )
  .frame(width: 320)
  .fixedSize(horizontal: false, vertical: true)
  .padding()
}

#Preview("Kitchen · Full Bruce · large text") {
  HomeAssistantTemperatureCard(
    reading: sensorlessKitchen, mode: .full, showsControl: true, isControlEnabled: true,
    showsAdjustmentControl: true
  )
  .environment(\.dynamicTypeSize, .accessibility3)
  .frame(width: 320)
  .fixedSize(horizontal: false, vertical: true)
  .padding()
}

private let sensorlessKitchen = HomeAssistantTemperatureReading(
  id: "climate.kitchen", name: "Kitchen", value: nil, targetValue: nil,
  unit: "°C", powerState: .off, kind: .zone, operatingMode: .off,
  opening: HomeAssistantZoneOpening(
    entityID: "cover.kitchen_damper", value: 5, isAvailable: true, supportsPosition: true
  )
)

#Preview("Kitchen · wide card") {
  HomeAssistantTemperatureCard(
    reading: sensorlessKitchen, mode: .standard, showsControl: true, isControlEnabled: true,
    showsAdjustmentControl: true
  )
  .frame(width: 700)
  .fixedSize(horizontal: false, vertical: true)
  .padding()
}

#Preview("Target and Vent · matching widths") {
  VStack(spacing: 14) {
    HomeAssistantTemperatureCard(
      reading: HomeAssistantTemperatureReading(
        id: "climate.lounge", name: "Lounge", value: 22, targetValue: 24,
        unit: "°C", powerState: .poweredOn, kind: .zone
      ),
      mode: .standard, showsControl: true, isControlEnabled: true, showsAdjustmentControl: true
    )
    HomeAssistantTemperatureCard(
      reading: sensorlessKitchen, mode: .standard,
      showsControl: true, isControlEnabled: true, showsAdjustmentControl: true
    )
  }
  .frame(width: 700)
  .fixedSize(horizontal: false, vertical: true)
  .padding()
}
