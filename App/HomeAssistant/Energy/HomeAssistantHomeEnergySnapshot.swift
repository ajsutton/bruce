struct HomeAssistantHomeEnergySnapshot: Equatable, Sendable {
  let pvPowerKilowatts: Double?
  let batteryStateOfCharge: Double?
  let homeConsumptionKilowatts: Double?
  let gridPowerKilowatts: Double?

  static let unavailable = HomeAssistantHomeEnergySnapshot(
    pvPowerKilowatts: nil,
    batteryStateOfCharge: nil,
    homeConsumptionKilowatts: nil,
    gridPowerKilowatts: nil
  )

  var hasReadings: Bool {
    pvPowerKilowatts != nil
      || batteryStateOfCharge != nil
      || homeConsumptionKilowatts != nil
      || gridPowerKilowatts != nil
  }
}
