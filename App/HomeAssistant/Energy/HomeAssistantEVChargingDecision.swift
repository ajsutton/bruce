import Foundation

struct HomeAssistantEVChargingDecision: Equatable, Sendable {
  static let desiredEntityID = "input_boolean.ev_charging_desired"
  static let overnightSafeChargingTimeEntityID =
    "sensor.ev_overnight_safe_charging_time"
  static let priceAllowsChargingEntityID =
    "input_boolean.ev_price_allows_charging"

  let isChargingDesired: Bool?
  let overnightSafeChargingMinutes: Double?
  let priceAllowsCharging: Bool?
  let currentPriceDollarsPerKilowattHour: Double?
  let batteryStateOfCharge: Double?

  static let unavailable = HomeAssistantEVChargingDecision(
    isChargingDesired: nil,
    overnightSafeChargingMinutes: nil,
    priceAllowsCharging: nil,
    currentPriceDollarsPerKilowattHour: nil,
    batteryStateOfCharge: nil
  )
}

extension HomeAssistantEVChargingDecision {
  init(states: [HomeAssistantState]) {
    func state(_ entityID: String) -> String? {
      states.first(where: { $0.entityID == entityID && $0.isAvailable })?.state
    }

    func boolean(_ entityID: String) -> Bool? {
      switch state(entityID) {
      case "on": true
      case "off": false
      default: nil
      }
    }

    func number(_ entityID: String) -> Double? {
      guard let rawValue = state(entityID), let value = Double(rawValue), value.isFinite else {
        return nil
      }
      return value
    }

    self.init(
      isChargingDesired: boolean(Self.desiredEntityID),
      overnightSafeChargingMinutes: number(
        Self.overnightSafeChargingTimeEntityID
      ).flatMap { (0...1_440).contains($0) ? $0 : nil },
      priceAllowsCharging: boolean(Self.priceAllowsChargingEntityID),
      currentPriceDollarsPerKilowattHour: number(
        HomeAssistantHomeEnergySnapshot.generalPriceEntityID
      ),
      batteryStateOfCharge: number(
        HomeAssistantHomeEnergySnapshot.batteryStateOfChargeEntityID
      ).flatMap { (0...100).contains($0) ? $0 : nil }
    )
  }
}
