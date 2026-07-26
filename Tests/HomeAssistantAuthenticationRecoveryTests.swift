import XCTest

@testable import Bruce

final class HomeAssistantAuthenticationRecoveryTests: XCTestCase {
  func testBrowserPresentationAndEndedSessionHaveDistinctRecovery() {
    XCTAssertEqual(
      HomeAssistantAuthenticationProblemMapper.problem(
        for: HomeAssistantWebAuthenticationError.presentationFailed("Not associated")
      ),
      .browserUnavailable
    )
    XCTAssertEqual(
      HomeAssistantAuthenticationProblemMapper.problem(
        for: HomeAssistantWebAuthenticationError.sessionEnded("Cancelled")
      ),
      .browserSessionEnded
    )
    XCTAssertEqual(
      HomeAssistantAuthenticationProblemMapper.problem(
        for: HomeAssistantAuthenticationError.presentationUnavailable
      ),
      .browserUnavailable
    )
  }

  func testOfflineURLFailureUsesGenericNetworkRecovery() {
    XCTAssertEqual(
      HomeAssistantAuthenticationProblemMapper.problem(
        for: URLError(.notConnectedToInternet)
      ),
      .unavailable
    )
  }
}
