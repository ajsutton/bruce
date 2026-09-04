import XCTest

@testable import Bruce

struct SchedulingUnusedHomeEnergyLoader: HomeAssistantHomeEnergyLoading {
  func loadHomeEnergySnapshot() async throws -> HomeAssistantHomeEnergySnapshot {
    throw HomeAssistantAPIError.invalidResponse
  }
}

func assertInitialPartialTotals(_ snapshot: HomeAssistantHomeEnergySnapshot) {
  XCTAssertEqual(snapshot.importCostLast24HoursDollars, 0.20)
  XCTAssertEqual(snapshot.importCostLast24HoursStatus, .current)
  XCTAssertEqual(snapshot.feedInEarningsLast24HoursStatus, .failed)
}

func assertComplementaryPartialTotals(_ snapshot: HomeAssistantHomeEnergySnapshot) {
  XCTAssertEqual(snapshot.importCostLast24HoursDollars, 0.20)
  XCTAssertEqual(snapshot.feedInEarningsLast24HoursDollars, 0.91)
  XCTAssertEqual(snapshot.importCostLast24HoursStatus, .failed)
  XCTAssertEqual(snapshot.feedInEarningsLast24HoursStatus, .current)
}

func assertSecondPartialRetryDeadline(_ deadline: Date?, startingAt timestamp: Date) {
  XCTAssertEqual(
    deadline,
    timestamp.addingTimeInterval(
      2 * HomeAssistantRollingEnergyRefreshState.failureRetryInterval
    )
  )
}
