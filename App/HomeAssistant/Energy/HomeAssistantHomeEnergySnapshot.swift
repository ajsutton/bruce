import Foundation

struct HomeAssistantHomeEnergySnapshot: Equatable, Sendable {
  static let pvPowerEntityID = "sensor.sigen_plant_pv_power"
  static let batteryStateOfChargeEntityID =
    "sensor.sigen_plant_battery_state_of_charge"
  static let batteryPowerEntityID = "sensor.sigen_plant_battery_power"
  static let homeConsumptionEntityID = "sensor.sigen_plant_consumed_power"
  static let gridPowerEntityID = "sensor.sigen_plant_grid_active_power"
  static let generalPriceEntityID =
    "sensor.01krmdgkh60wyckeepvgtbbgv3_general_price"
  static let feedInPriceEntityID =
    "sensor.01krmdgkh60wyckeepvgtbbgv3_feed_in_price"

  let pvPowerKilowatts: Double?
  let batteryStateOfCharge: Double?
  let batteryPowerKilowatts: Double?
  let homeConsumptionKilowatts: Double?
  let gridPowerKilowatts: Double?
  let generalPriceDollarsPerKilowattHour: Double?
  let feedInPriceDollarsPerKilowattHour: Double?

  init(
    pvPowerKilowatts: Double?,
    batteryStateOfCharge: Double?,
    batteryPowerKilowatts: Double? = nil,
    homeConsumptionKilowatts: Double?,
    gridPowerKilowatts: Double?,
    generalPriceDollarsPerKilowattHour: Double?,
    feedInPriceDollarsPerKilowattHour: Double?
  ) {
    self.pvPowerKilowatts = pvPowerKilowatts
    self.batteryStateOfCharge = batteryStateOfCharge
    self.batteryPowerKilowatts = batteryPowerKilowatts
    self.homeConsumptionKilowatts = homeConsumptionKilowatts
    self.gridPowerKilowatts = gridPowerKilowatts
    self.generalPriceDollarsPerKilowattHour = generalPriceDollarsPerKilowattHour
    self.feedInPriceDollarsPerKilowattHour = feedInPriceDollarsPerKilowattHour
  }

  static let unavailable = HomeAssistantHomeEnergySnapshot(
    pvPowerKilowatts: nil,
    batteryStateOfCharge: nil,
    batteryPowerKilowatts: nil,
    homeConsumptionKilowatts: nil,
    gridPowerKilowatts: nil,
    generalPriceDollarsPerKilowattHour: nil,
    feedInPriceDollarsPerKilowattHour: nil
  )

  var hasReadings: Bool {
    pvPowerKilowatts != nil
      || batteryStateOfCharge != nil
      || batteryPowerKilowatts != nil
      || homeConsumptionKilowatts != nil
      || gridPowerKilowatts != nil
      || generalPriceDollarsPerKilowattHour != nil
      || feedInPriceDollarsPerKilowattHour != nil
  }

  func hasAvailabilityTransition(from previous: Self) -> Bool {
    [
      pvPowerKilowatts != nil,
      batteryStateOfCharge != nil,
      batteryPowerKilowatts != nil,
      homeConsumptionKilowatts != nil,
      gridPowerKilowatts != nil,
      generalPriceDollarsPerKilowattHour != nil,
      feedInPriceDollarsPerKilowattHour != nil,
    ] != [
      previous.pvPowerKilowatts != nil,
      previous.batteryStateOfCharge != nil,
      previous.batteryPowerKilowatts != nil,
      previous.homeConsumptionKilowatts != nil,
      previous.gridPowerKilowatts != nil,
      previous.generalPriceDollarsPerKilowattHour != nil,
      previous.feedInPriceDollarsPerKilowattHour != nil,
    ]
  }

  func hasSamePresentation(as other: Self) -> Bool {
    Self.quantize(pvPowerKilowatts, scale: 10)
      == Self.quantize(other.pvPowerKilowatts, scale: 10)
      && Self.batteryPresentation(batteryStateOfCharge)
        == Self.batteryPresentation(other.batteryStateOfCharge)
      && Self.quantize(homeConsumptionKilowatts, scale: 10)
        == Self.quantize(other.homeConsumptionKilowatts, scale: 10)
      && Self.gridPresentation(gridPowerKilowatts)
        == Self.gridPresentation(other.gridPowerKilowatts)
      && Self.pricePresentation(generalPriceDollarsPerKilowattHour)
        == Self.pricePresentation(other.generalPriceDollarsPerKilowattHour)
      && Self.feedInPresentation(feedInPriceDollarsPerKilowattHour)
        == Self.feedInPresentation(other.feedInPriceDollarsPerKilowattHour)
  }

  private static func quantize(_ value: Double?, scale: Double) -> Double? {
    value.map { ($0 * scale).rounded(.toNearestOrEven) / scale }
  }

  private static func pricePresentation(_ value: Double?) -> String? {
    value.map {
      ($0 * 100).formatted(
        .number
          .locale(.current)
          .precision(.fractionLength(0...1))
      )
    }
  }

  private struct BatteryPresentation: Equatable {
    let value: Double
    let band: Int
  }

  private static func batteryPresentation(
    _ value: Double?
  ) -> BatteryPresentation? {
    guard let value else { return nil }
    let band =
      switch value {
      case ..<20: 0
      case ..<25: 1
      case ..<50: 2
      case ..<75: 3
      default: 4
      }
    return BatteryPresentation(
      value: quantize(value, scale: 1) ?? value,
      band: band
    )
  }

  private enum GridPresentation: Equatable {
    case exporting(Double)
    case idle
    case importing(Double)
  }

  private static func gridPresentation(_ value: Double?) -> GridPresentation? {
    guard let value else { return nil }
    if value <= -0.1 {
      return .exporting(quantize(abs(value), scale: 10) ?? abs(value))
    }
    if value >= 0.1 {
      return .importing(quantize(value, scale: 10) ?? value)
    }
    return .idle
  }

  private struct FeedInPresentation: Equatable {
    let value: String
    let isCharge: Bool
  }

  private static func feedInPresentation(
    _ value: Double?
  ) -> FeedInPresentation? {
    guard let value else { return nil }
    return FeedInPresentation(
      value: pricePresentation(abs(value)) ?? "",
      isCharge: value < 0
    )
  }
}
