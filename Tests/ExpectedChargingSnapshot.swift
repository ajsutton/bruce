@testable import Bruce

struct ExpectedChargingSnapshot {
  let mode: HomeAssistantEVChargingMode
  let activity: HomeAssistantEVChargingActivity
  let decision: HomeAssistantEVChargingDecision

  static let initial = ExpectedChargingSnapshot(
    mode: .smart,
    activity: .connected,
    decision: decision(
      desired: false,
      safeMinutes: 48,
      price: 0.341,
      battery: 76
    )
  )

  static let updated = ExpectedChargingSnapshot(
    mode: .charging,
    activity: .charging(powerWatts: 7_024),
    decision: decision(
      desired: true,
      safeMinutes: 108,
      price: 0.292,
      battery: 68
    )
  )

  private static func decision(
    desired: Bool,
    safeMinutes: Double,
    price: Double,
    battery: Double
  ) -> HomeAssistantEVChargingDecision {
    HomeAssistantEVChargingDecision(
      isChargingDesired: desired,
      overnightSafeChargingMinutes: safeMinutes,
      priceAllowsCharging: true,
      currentPriceDollarsPerKilowattHour: price,
      batteryStateOfCharge: battery
    )
  }
}
