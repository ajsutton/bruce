import XCTest

@testable import Bruce

final class HomeAssistantConnectionBannerTests: XCTestCase {
  func testPresentationProblemTakesPriorityOverServerProblem() {
    let banner = HomeAssistantConnectionBanner(
      presentationProblem: .restoreFailed,
      serverStatus: status(.unavailable)
    )

    XCTAssertEqual(banner?.problem, .presentation(.restoreFailed))
    XCTAssertEqual(banner?.action, .manageConnection)
  }

  func testUnavailableServerOffersRefresh() {
    let banner = HomeAssistantConnectionBanner(
      presentationProblem: nil,
      serverStatus: status(.unavailable)
    )

    XCTAssertEqual(banner?.problem, .unavailable)
    XCTAssertEqual(banner?.action, .refresh)
  }

  func testReconnectingServerDoesNotOfferAnAction() {
    let banner = HomeAssistantConnectionBanner(
      presentationProblem: nil,
      serverStatus: status(.reconnecting)
    )

    XCTAssertEqual(banner?.problem, .reconnecting)
    XCTAssertEqual(banner?.action, HomeAssistantConnectionBanner.Action.none)
  }

  func testHealthyServerDoesNotCreateConnectionBanner() {
    XCTAssertNil(
      HomeAssistantConnectionBanner(
        presentationProblem: nil,
        serverStatus: status(.live)
      )
    )
  }

  func testSharedReadProblemsAreHiddenWithServerBanner() {
    XCTAssertFalse(HomeAssistantTemperatureStore.Problem.invalidResponse.isFeatureSpecific)
    XCTAssertFalse(HomeAssistantEVChargingStore.Problem.invalidResponse.isFeatureSpecific)
    XCTAssertFalse(HomeAssistantGarageDoorStore.Problem.invalidResponse.isFeatureSpecific)
    XCTAssertFalse(HomeAssistantHomeEnergyStore.Problem.invalidResponse.isFeatureSpecific)
  }

  func testCommandProblemsRemainVisibleWithServerBanner() {
    XCTAssertTrue(HomeAssistantEVChargingStore.Problem.updateFailed.isFeatureSpecific)
    XCTAssertTrue(HomeAssistantEVChargingStore.Problem.updateTimedOut.isFeatureSpecific)
    XCTAssertTrue(HomeAssistantGarageDoorStore.Problem.updateFailed.isFeatureSpecific)
  }

  private func status(
    _ phase: HomeAssistantServerStatus.Phase
  ) -> HomeAssistantServerStatus {
    HomeAssistantServerStatus(phase: phase, lastSuccessfulUpdate: nil)
  }
}
