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
  let importCostLast24HoursDollars: Double?
  let feedInEarningsLast24HoursDollars: Double?
  let readingsAreCurrent: Bool
  let importCostIsCurrent: Bool
  let feedInEarningsIsCurrent: Bool
  let readingsCapturedAt: Date
  let importCostCapturedAt: Date
  let feedInEarningsCapturedAt: Date

  init(
    sourceIdentifier: String = "preview",
    capturedAt: Date,
    pvPowerKilowatts: Double?,
    batteryStateOfCharge: Double?,
    homeConsumptionKilowatts: Double?,
    gridPowerKilowatts: Double?,
    generalPriceDollarsPerKilowattHour: Double?,
    feedInPriceDollarsPerKilowattHour: Double?,
    importCostLast24HoursDollars: Double?,
    feedInEarningsLast24HoursDollars: Double?,
    readingsAreCurrent: Bool = true,
    importCostIsCurrent: Bool = true,
    feedInEarningsIsCurrent: Bool = true,
    readingsCapturedAt: Date? = nil,
    importCostCapturedAt: Date? = nil,
    feedInEarningsCapturedAt: Date? = nil,
  ) {
    self.sourceIdentifier = sourceIdentifier
    self.capturedAt = capturedAt
    self.pvPowerKilowatts = pvPowerKilowatts
    self.batteryStateOfCharge = batteryStateOfCharge
    self.homeConsumptionKilowatts = homeConsumptionKilowatts
    self.gridPowerKilowatts = gridPowerKilowatts
    self.generalPriceDollarsPerKilowattHour = generalPriceDollarsPerKilowattHour
    self.feedInPriceDollarsPerKilowattHour = feedInPriceDollarsPerKilowattHour
    self.importCostLast24HoursDollars = importCostLast24HoursDollars
    self.feedInEarningsLast24HoursDollars = feedInEarningsLast24HoursDollars
    self.readingsAreCurrent = readingsAreCurrent
    self.importCostIsCurrent = importCostIsCurrent
    self.feedInEarningsIsCurrent = feedInEarningsIsCurrent
    self.readingsCapturedAt = readingsCapturedAt ?? capturedAt
    self.importCostCapturedAt = importCostCapturedAt ?? capturedAt
    self.feedInEarningsCapturedAt = feedInEarningsCapturedAt ?? capturedAt
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
      && importCostLast24HoursDollars == other.importCostLast24HoursDollars
      && feedInEarningsLast24HoursDollars == other.feedInEarningsLast24HoursDollars
      && readingsAreCurrent == other.readingsAreCurrent
      && importCostIsCurrent == other.importCostIsCurrent
      && feedInEarningsIsCurrent == other.feedInEarningsIsCurrent
  }

  var oldestDisplayedCapture: Date {
    var captures: [Date] = []
    if hasLiveReadings { captures.append(readingsCapturedAt) }
    if importCostLast24HoursDollars != nil { captures.append(importCostCapturedAt) }
    if feedInEarningsLast24HoursDollars != nil { captures.append(feedInEarningsCapturedAt) }
    return captures.min() ?? capturedAt
  }

  private var hasLiveReadings: Bool {
    pvPowerKilowatts != nil
      || batteryStateOfCharge != nil
      || homeConsumptionKilowatts != nil
      || gridPowerKilowatts != nil
      || generalPriceDollarsPerKilowattHour != nil
      || feedInPriceDollarsPerKilowattHour != nil
  }

}
