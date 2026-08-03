import Foundation

struct HomeEnergyWidgetSnapshot: Codable, Equatable, Sendable {
  let sourceIdentifier: String
  let capturedAt: Date
  let pvPowerKilowatts: Double?
  let batteryStateOfCharge: Double?
  let homeConsumptionKilowatts: Double?
  let gridPowerKilowatts: Double?
  let generalPriceDollarsPerKilowattHour: Double?
  let feedInPriceDollarsPerKilowattHour: Double?
  let importCostTodayDollars: Double?
  let feedInEarningsTodayDollars: Double?
  let readingsAreCurrent: Bool
  let importCostIsCurrent: Bool
  let feedInEarningsIsCurrent: Bool
  let readingsCapturedAt: Date
  let importCostCapturedAt: Date
  let feedInEarningsCapturedAt: Date
  let dailyEnergyInterval: DateInterval?

  init(
    sourceIdentifier: String = "preview",
    capturedAt: Date,
    pvPowerKilowatts: Double?,
    batteryStateOfCharge: Double?,
    homeConsumptionKilowatts: Double?,
    gridPowerKilowatts: Double?,
    generalPriceDollarsPerKilowattHour: Double?,
    feedInPriceDollarsPerKilowattHour: Double?,
    importCostTodayDollars: Double?,
    feedInEarningsTodayDollars: Double?,
    readingsAreCurrent: Bool = true,
    importCostIsCurrent: Bool = true,
    feedInEarningsIsCurrent: Bool = true,
    readingsCapturedAt: Date? = nil,
    importCostCapturedAt: Date? = nil,
    feedInEarningsCapturedAt: Date? = nil,
    dailyEnergyInterval: DateInterval? = nil
  ) {
    self.sourceIdentifier = sourceIdentifier
    self.capturedAt = capturedAt
    self.pvPowerKilowatts = pvPowerKilowatts
    self.batteryStateOfCharge = batteryStateOfCharge
    self.homeConsumptionKilowatts = homeConsumptionKilowatts
    self.gridPowerKilowatts = gridPowerKilowatts
    self.generalPriceDollarsPerKilowattHour = generalPriceDollarsPerKilowattHour
    self.feedInPriceDollarsPerKilowattHour = feedInPriceDollarsPerKilowattHour
    self.importCostTodayDollars = importCostTodayDollars
    self.feedInEarningsTodayDollars = feedInEarningsTodayDollars
    self.readingsAreCurrent = readingsAreCurrent
    self.importCostIsCurrent = importCostIsCurrent
    self.feedInEarningsIsCurrent = feedInEarningsIsCurrent
    self.readingsCapturedAt = readingsCapturedAt ?? capturedAt
    self.importCostCapturedAt = importCostCapturedAt ?? capturedAt
    self.feedInEarningsCapturedAt = feedInEarningsCapturedAt ?? capturedAt
    self.dailyEnergyInterval = dailyEnergyInterval
  }

  func hasSameReadings(as other: Self) -> Bool {
    pvPowerKilowatts == other.pvPowerKilowatts
      && batteryStateOfCharge == other.batteryStateOfCharge
      && homeConsumptionKilowatts == other.homeConsumptionKilowatts
      && gridPowerKilowatts == other.gridPowerKilowatts
      && generalPriceDollarsPerKilowattHour
        == other.generalPriceDollarsPerKilowattHour
      && feedInPriceDollarsPerKilowattHour
        == other.feedInPriceDollarsPerKilowattHour
      && importCostTodayDollars == other.importCostTodayDollars
      && feedInEarningsTodayDollars == other.feedInEarningsTodayDollars
      && readingsAreCurrent == other.readingsAreCurrent
      && importCostIsCurrent == other.importCostIsCurrent
      && feedInEarningsIsCurrent == other.feedInEarningsIsCurrent
  }

  var oldestLastKnownCapture: Date? {
    var captures: [Date] = []
    if !readingsAreCurrent { captures.append(readingsCapturedAt) }
    if !importCostIsCurrent { captures.append(importCostCapturedAt) }
    if !feedInEarningsIsCurrent { captures.append(feedInEarningsCapturedAt) }
    return captures.min()
  }

  static func interval(_ interval: DateInterval?, contains timestamp: Date) -> Bool {
    guard let interval else { return false }
    return interval.start <= timestamp && timestamp < interval.end
  }
}
