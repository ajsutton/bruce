extension HomeAssistantEVChargingSnapshot {
  init(states: [HomeAssistantState]) throws {
    func homeAssistantState(_ entityID: String) -> HomeAssistantState? {
      states.first { $0.entityID == entityID }
    }

    func state(_ entityID: String) -> String? {
      homeAssistantState(entityID)?.state
    }

    guard
      let modeEntity = homeAssistantState("input_select.ev_charging_mode"),
      let mode = HomeAssistantEVChargingMode(rawValue: modeEntity.state),
      let modeLastUpdated = modeEntity.lastUpdated
    else {
      throw HomeAssistantAPIError.invalidResponse
    }

    self.init(
      mode: mode,
      activity: Self.activity(
        mode: mode,
        sourceState: EVChargingSourceState(
          powerWatts: state("sensor.home_myenergi_home_power_charging").flatMap(Double.init),
          plugState: state("sensor.zappi_myenergi_zappi_26482259_plug_status"),
          chargerState: state("sensor.zappi_myenergi_zappi_26482259_status"),
          batteryAllowsCharging: state("input_boolean.ev_smart_battery_allows_charging"),
          priceAllowsCharging: state("input_boolean.ev_price_allows_charging")
        )
      ),
      modeLastUpdated: modeLastUpdated
    )
  }

  private static func activity(
    mode: HomeAssistantEVChargingMode,
    sourceState: EVChargingSourceState
  ) -> HomeAssistantEVChargingActivity {
    if let powerWatts = sourceState.powerWatts, powerWatts.isFinite, powerWatts > 50 {
      return .charging(powerWatts: powerWatts)
    }
    if sourceState.plugState == "EV Disconnected" {
      return .notPluggedIn
    }
    if sourceState.plugState == "Charging" {
      return .charging(powerWatts: nil)
    }
    if mode == .off {
      return .switchedOff
    }
    if sourceState.chargerState == "Completed" {
      return .complete
    }
    if sourceState.priceAllowsCharging == "off" {
      return .paused(reason: .electricityPrice)
    }
    if mode == .smart, sourceState.batteryAllowsCharging == "off" {
      return .paused(reason: .homeBattery)
    }
    if sourceState.plugState == "Waiting for EV" {
      return .waitingForVehicle
    }
    if sourceState.chargerState == "Paused" {
      return .paused(reason: nil)
    }
    if sourceState.plugState == "EV Connected" {
      return .connected
    }
    return .unavailable
  }
}

private struct EVChargingSourceState {
  let powerWatts: Double?
  let plugState: String?
  let chargerState: String?
  let batteryAllowsCharging: String?
  let priceAllowsCharging: String?
}
