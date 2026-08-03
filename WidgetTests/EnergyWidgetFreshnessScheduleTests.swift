import XCTest

final class EnergyWidgetFreshnessScheduleTests: XCTestCase {
  func testAgeIsCurrentUntilTheFirstWholeMinute() {
    let reference = Date(timeIntervalSince1970: 1_000)

    XCTAssertEqual(
      EnergyWidgetFreshnessSchedule.wholeMinutes(
        from: reference,
        to: reference.addingTimeInterval(59.9)
      ),
      0
    )
    XCTAssertEqual(
      EnergyWidgetFreshnessSchedule.wholeMinutes(
        from: reference,
        to: reference.addingTimeInterval(60)
      ),
      1
    )
  }

  func testScheduleKeepsMinuteAgesMovingWhenPreferredRefreshIsDelayed() {
    let reference = Date(timeIntervalSince1970: 1_000)
    let start = reference.addingTimeInterval(20)

    let dates = EnergyWidgetFreshnessSchedule.entryDates(
      referenceDate: reference,
      startingAt: start
    )

    XCTAssertEqual(dates[0], start)
    XCTAssertEqual(dates[1], reference.addingTimeInterval(60))
    XCTAssertTrue(try XCTUnwrap(dates.last) > start.addingTimeInterval(90 * 60))
  }
}
