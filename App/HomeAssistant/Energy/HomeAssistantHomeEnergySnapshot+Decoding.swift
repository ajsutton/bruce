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

    pvPowerKilowatts = value(Self.pvPowerEntityID).flatMap {
      $0 >= 0 ? $0 : nil
    }
    batteryStateOfCharge = value(
      Self.batteryStateOfChargeEntityID
    ).flatMap {
      (0...100).contains($0) ? $0 : nil
    }
    batteryPowerKilowatts = value(Self.batteryPowerEntityID).map { -$0 }
    homeConsumptionKilowatts = value(
      Self.homeConsumptionEntityID
    ).flatMap {
      $0 >= 0 ? $0 : nil
    }
    gridPowerKilowatts = value(Self.gridPowerEntityID)
    generalPriceDollarsPerKilowattHour = value(
      Self.generalPriceEntityID
    )
    feedInPriceDollarsPerKilowattHour = value(
      Self.feedInPriceEntityID
    )
  }
}
