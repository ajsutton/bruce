extension HomeAssistantHomeEnergySnapshot {
  init(states: [HomeAssistantState]) {
    func value(_ entityID: String) -> Double? {
      guard
        let state = states.first(where: { $0.entityID == entityID })?.state,
        let value = Double(state),
        value.isFinite
      else {
        return nil
      }
      return value
    }

    pvPowerKilowatts = value("sensor.sigen_plant_pv_power").flatMap {
      $0 >= 0 ? $0 : nil
    }
    batteryStateOfCharge = value(
      Self.batteryStateOfChargeEntityID
    ).flatMap {
      (0...100).contains($0) ? $0 : nil
    }
    homeConsumptionKilowatts = value(
      "sensor.sigen_plant_consumed_power"
    ).flatMap {
      $0 >= 0 ? $0 : nil
    }
    gridPowerKilowatts = value("sensor.sigen_plant_grid_active_power")
    generalPriceDollarsPerKilowattHour = value(
      Self.generalPriceEntityID
    )
    feedInPriceDollarsPerKilowattHour = value(
      Self.feedInPriceEntityID
    )
    requiresHistoryBackfill = false
  }
}
