import Foundation
import XCTest

@testable import Bruce

final class HomeAssistantServerStatusTests: XCTestCase {
  func testRecentSuccessfulUpdateDoesNotNeedAVisibleTimestamp() {
    let date = Date(timeIntervalSince1970: 100)
    let status = HomeAssistantServerStatus(phase: .live, lastSuccessfulUpdate: date)

    XCTAssertNil(status.lastSuccessfulUpdateForDisplay(at: date.addingTimeInterval(60)))
  }

  func testOlderSuccessfulUpdateIsVisible() {
    let date = Date(timeIntervalSince1970: 100)
    let status = HomeAssistantServerStatus(phase: .live, lastSuccessfulUpdate: date)

    XCTAssertEqual(
      status.lastSuccessfulUpdateForDisplay(
        at: date.addingTimeInterval(HomeAssistantServerStatus.recentUpdateInterval)
      ),
      date
    )
  }

  func testTimestampRefreshOccursAtFreshnessBoundary() {
    let date = Date(timeIntervalSince1970: 100)

    XCTAssertEqual(
      HomeAssistantServerStatus.nextTimestampRefresh(
        after: date.addingTimeInterval(299),
        lastSuccessfulUpdate: date
      ),
      date.addingTimeInterval(HomeAssistantServerStatus.recentUpdateInterval)
    )
  }

  func testTimestampRefreshContinuesEachMinuteAfterFreshnessBoundary() {
    let date = Date(timeIntervalSince1970: 100)
    let currentDate = date.addingTimeInterval(301)

    XCTAssertEqual(
      HomeAssistantServerStatus.nextTimestampRefresh(
        after: currentDate,
        lastSuccessfulUpdate: date
      ),
      currentDate.addingTimeInterval(60)
    )
  }

  func testLiveUpdateRecordsSuccessfulUpdateTime() {
    let date = Date(timeIntervalSince1970: 100)

    let status = HomeAssistantServerStatus.idle.receiving(.live([]), at: date)

    XCTAssertEqual(status, HomeAssistantServerStatus(phase: .live, lastSuccessfulUpdate: date))
  }

  func testRefreshPreservesLastSuccessfulUpdateTime() {
    let date = Date(timeIntervalSince1970: 100)
    let live = HomeAssistantServerStatus(phase: .live, lastSuccessfulUpdate: date)

    let refreshing = live.receiving(.refreshing([]), at: date.addingTimeInterval(10))

    XCTAssertEqual(
      refreshing,
      HomeAssistantServerStatus(phase: .updating, lastSuccessfulUpdate: date)
    )
  }

  func testReconnectPreservesLastSuccessfulUpdateUntilRecovery() {
    let firstDate = Date(timeIntervalSince1970: 100)
    let recoveryDate = Date(timeIntervalSince1970: 120)
    let live = HomeAssistantServerStatus(phase: .live, lastSuccessfulUpdate: firstDate)

    let reconnecting = live.receiving(.reconnecting([]), at: recoveryDate)
    let recovered = reconnecting.receiving(.live([]), at: recoveryDate)

    XCTAssertEqual(reconnecting.lastSuccessfulUpdate, firstDate)
    XCTAssertEqual(reconnecting.phase, .reconnecting)
    XCTAssertEqual(recovered.lastSuccessfulUpdate, recoveryDate)
    XCTAssertEqual(recovered.phase, .live)
  }

  func testConnectionFailurePreservesLastSuccessfulUpdateTime() {
    let date = Date(timeIntervalSince1970: 100)
    let live = HomeAssistantServerStatus(phase: .live, lastSuccessfulUpdate: date)

    let unavailable = live.receiving(error: URLError(.networkConnectionLost))

    XCTAssertEqual(
      unavailable,
      HomeAssistantServerStatus(phase: .unavailable, lastSuccessfulUpdate: date)
    )
  }

  func testAuthenticationFailureRequiresSignIn() {
    let status = HomeAssistantServerStatus.idle.receiving(
      error: HomeAssistantAPIError.unauthorized
    )

    XCTAssertEqual(status.phase, .signInRequired)
  }
}
