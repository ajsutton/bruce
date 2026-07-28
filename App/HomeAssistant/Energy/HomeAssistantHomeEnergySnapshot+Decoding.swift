import Foundation

extension HomeAssistantHomeEnergySnapshot {
  init(homeAssistantStates data: Data) throws {
    let states: [HomeAssistantState]
    do {
      states = try JSONDecoder().decode([HomeAssistantState].self, from: data)
    } catch {
      throw HomeAssistantAPIError.invalidResponse
    }

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
      "sensor.sigen_plant_battery_state_of_charge"
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
      "sensor.01krmdgkh60wyckeepvgtbbgv3_general_price"
    )
    feedInPriceDollarsPerKilowattHour = value(
      "sensor.01krmdgkh60wyckeepvgtbbgv3_feed_in_price"
    )
  }
}
