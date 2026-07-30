struct HomeAssistantHomeEnergySnapshot: Equatable, Sendable {
  static let batteryStateOfChargeEntityID =
    "sensor.sigen_plant_battery_state_of_charge"
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
  var requiresHistoryBackfill = false

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

  func requiringHistoryBackfill() -> Self {
    var snapshot = self
    snapshot.requiresHistoryBackfill = true
    return snapshot
  }
}
