extension HomeAssistantHomeEnergySnapshot {
  init(states: [HomeAssistantState]) {
    func entity(_ entityID: String) -> HomeAssistantState? {
      states.first(where: { $0.entityID == entityID })
    }

    func value(_ entityID: String) -> Double? {
      guard
        let state = entity(entityID)?.state,
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
    importCostTodayDollars = nil
    feedInEarningsTodayDollars = nil
    importCostCounterDollars = value(Self.importCostEntityID)
    feedInEarningsCounterDollars = value(Self.feedInEarningsEntityID)
    importCostCounterLastReset = entity(Self.importCostEntityID)?.lastReset
    feedInEarningsCounterLastReset =
      entity(Self.feedInEarningsEntityID)?.lastReset
    importCostTodayStatus = .current
    feedInEarningsTodayStatus = .current
  }
}
