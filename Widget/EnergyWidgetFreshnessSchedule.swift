import Foundation

enum EnergyWidgetFreshnessSchedule {
  static let coverage: TimeInterval = 2 * 60 * 60

  static func entryDates(
    referenceDate: Date,
    startingAt startDate: Date,
    coverageDuration: TimeInterval = coverage
  ) -> [Date] {
    let coverageDate = startDate.addingTimeInterval(coverageDuration)
    let elapsed = max(0, startDate.timeIntervalSince(referenceDate))
    var nextDate = referenceDate.addingTimeInterval((floor(elapsed / 60) + 1) * 60)
    var dates = [startDate]
    while nextDate < coverageDate {
      dates.append(nextDate)
      nextDate.addTimeInterval(60)
    }
    return dates
  }

  static func wholeMinutes(from referenceDate: Date, to date: Date) -> Int {
    max(0, Int(date.timeIntervalSince(referenceDate) / 60))
  }
}
