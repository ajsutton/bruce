struct HomeAssistantHomeEnergySnapshot: Equatable, Sendable {
  static let generalPriceEntityID =
    "sensor.01krmdgkh60wyckeepvgtbbgv3_general_price"
  static let feedInPriceEntityID =
    "sensor.01krmdgkh60wyckeepvgtbbgv3_feed_in_price"

  let pvPowerKilowatts: Double?
  let batteryStateOfCharge: Double?
  let homeConsumptionKilowatts: Double?
  let gridPowerKilowatts: Double?
  let generalPriceDollarsPerKilowattHour: Double?
  let feedInPriceDollarsPerKilowattHour: Double?

  static let unavailable = HomeAssistantHomeEnergySnapshot(
    pvPowerKilowatts: nil,
    batteryStateOfCharge: nil,
    homeConsumptionKilowatts: nil,
    gridPowerKilowatts: nil,
    generalPriceDollarsPerKilowattHour: nil,
    feedInPriceDollarsPerKilowattHour: nil
  )

  var hasReadings: Bool {
    pvPowerKilowatts != nil
      || batteryStateOfCharge != nil
      || homeConsumptionKilowatts != nil
      || gridPowerKilowatts != nil
      || generalPriceDollarsPerKilowattHour != nil
      || feedInPriceDollarsPerKilowattHour != nil
  }
}
